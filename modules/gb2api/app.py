import json
import logging
import os
import time
import uuid
from datetime import datetime
from typing import List, Optional, Union

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s | %(levelname)s | %(message)s')
logger = logging.getLogger(__name__)

# --- 配置区 ---
API_KEY = os.getenv("API_KEY", "sk-business-key")
PORT = int(os.getenv("PORT", 7860))
HOST = os.getenv("HOST", "0.0.0.0")
PROXY = os.getenv("http_proxy") or os.getenv("https_proxy") or os.getenv("all_proxy")
# 使用更现代、更真实的浏览器 UA
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

import types
import asyncio
import base64

# 账号管理
ACCOUNTS = []
accounts_file = os.path.join(os.path.dirname(__file__), "accounts.json")
last_accounts_mtime = 0

class AccountManager:
    def __init__(self):
        self.accounts = []
        self.lock = asyncio.Lock()
        
    def load_accounts(self, accounts_data):
        self.accounts = []
        for acc in accounts_data:
            acc_data = acc.copy()
            acc_data['cooldown_until'] = 0
            acc_data['fail_count'] = 0
            acc_data['session_name'] = None
            acc_data['session_expires'] = 0
            
            config = types.SimpleNamespace(
                secure_c_ses=acc['secure_c_ses'],
                host_c_oses=acc.get('host_c_oses', ''),
                csesidx=acc['csesidx'],
                account_id=acc['id']
            )
            
            # 【重要改进】启用 http2=True，模拟真实浏览器连接特征
            client = httpx.AsyncClient(
                proxy=PROXY, 
                verify=False, 
                http2=True, 
                timeout=httpx.Timeout(120.0, connect=30.0),
                limits=httpx.Limits(max_keepalive_connections=20, max_connections=50)
            )
            
            try:
                from core.jwt import JWTManager
                acc_data['jwt_mgr'] = JWTManager(config, client, USER_AGENT)
                acc_data['client'] = client # 共享 Client
            except ImportError:
                logger.error("未找到 core.jwt 模块")
            
            self.accounts.append(acc_data)
            
    async def get_next(self):
        async with self.lock:
            if not self.accounts:
                return None
            
            now = time.time()
            available = [a for a in self.accounts if a.get('cooldown_until', 0) <= now]
            
            if not available:
                # 即使在冷却，也允许强制尝试（缩短体感限流）
                best_acc = min(self.accounts, key=lambda a: a.get('cooldown_until', 0))
                return best_acc
                
            selected = available[0]
            self.accounts.remove(selected)
            self.accounts.append(selected)
            return selected

    async def report_status(self, email, status_code):
        async with self.lock:
            for acc in self.accounts:
                if acc['id'] == email:
                    if status_code in [401, 403]:
                        acc['cooldown_until'] = time.time() + 300 # 缩短到 5 分钟
                        logger.error(f"❌ 账号 {email} 会话失效。")
                    elif status_code == 429:
                        # 【大幅放宽】429 只冷却 5 秒，快速重试
                        acc['cooldown_until'] = time.time() + 5
                        logger.warning(f"⏳ 账号 {email} 触发 Google 频控，5秒后自动重试。")
                    elif status_code == 200:
                        acc['fail_count'] = 0
                        acc['cooldown_until'] = 0
                    break

picker = AccountManager()

def load_manual_accounts():
    global ACCOUNTS, picker, last_accounts_mtime
    if os.path.exists(accounts_file):
        try:
            mtime = os.path.getmtime(accounts_file)
            if mtime > last_accounts_mtime:
                with open(accounts_file, "r", encoding="utf-8") as f:
                    ACCOUNTS = json.load(f)
                    picker.load_accounts(ACCOUNTS)
                last_accounts_mtime = mtime
                logger.info(f"🔄 检测到 accounts.json 更新，已热重载 {len(ACCOUNTS)} 个账号！")
        except: pass

load_manual_accounts()

try:
    from core.google_api import create_google_session, get_common_headers
    from core.message import build_full_context_text
    from core.jwt import JWTManager
    from util.streaming_parser import parse_json_array_stream_async, parse_json_array_stream
except ImportError as e:
    logger.error(f"核心逻辑导入失败: {e}")

from pydantic import BaseModel

class Message(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    model: str = "gemini-auto"
    messages: List[Message]
    stream: bool = False
    temperature: Optional[float] = 0.7

app = FastAPI(title="GB2API (Stable)")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def create_chunk(id: str, created: int, model: str, delta: dict, finish_reason: Union[str, None]) -> str:
    return json.dumps({
        "id": id,
        "object": "chat.completion.chunk",
        "created": created,
        "model": model,
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish_reason}]
    })

@app.get("/v1/models")
async def list_models():
    models = ["gemini-auto", "gemini-2.5-flash", "gemini-2.5-pro", "gemini-3-flash-preview", "gemini-3-pro-preview", "gemini-3.1-pro-preview", "gemini-imagen", "gemini-veo"]
    data = [{"id": m, "object": "model", "created": int(time.time()), "owned_by": "google"} for m in models]
    return {"object": "list", "data": data}

@app.post("/v1/chat/completions")
async def chat_completions(request: Request, body: ChatRequest, authorization: str = Header(None)):
    load_manual_accounts()
    if API_KEY and (not authorization or authorization[7:] != API_KEY):
        raise HTTPException(status_code=401, detail="Invalid API Key")

    acc = await picker.get_next()
    if not acc: raise HTTPException(status_code=500, detail="No accounts")

    request_id = str(uuid.uuid4())[:8]
    client = acc['client'] # 复用账号专属的长连接 Client

    try:
        jwt = await acc['jwt_mgr'].get(request_id)
        headers = get_common_headers(jwt, USER_AGENT)
        
        # 获取或创建 Session
        now = time.time()
        if not acc.get('session_name') or now > acc.get('session_expires', 0):
            create_sess_body = {
                "configId": acc['config_id'],
                "additionalParams": {"token": "-"},
                "createSessionRequest": {"session": {"name": "", "displayName": ""}}
            }
            r_sess = await client.post("https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetCreateSession", headers=headers, json=create_sess_body)
            if r_sess.status_code == 200:
                acc['session_name'] = r_sess.json().get("session", {}).get("name", "")
                acc['session_expires'] = now + 1800
            else:
                await picker.report_status(acc['id'], r_sess.status_code)
                raise HTTPException(status_code=r_sess.status_code, detail="Session failed")
        
        session_name = acc['session_name']
        tools_spec = {"webGroundingSpec": {}, "toolRegistry": "default_tool_registry"}
        target_model_id = body.model
        if body.model == "gemini-imagen": tools_spec = {"imageGenerationSpec": {}}; target_model_id = None
        elif body.model == "gemini-veo": tools_spec = {"videoGenerationSpec": {}}; target_model_id = None
        elif body.model == "gemini-auto": target_model_id = None

        google_payload = {
            "configId": acc['config_id'],
            "additionalParams": {"token": "-"},
            "streamAssistRequest": {
                "session": session_name,
                "query": {"parts": [{"text": build_full_context_text(body.messages)}]},
                "answerGenerationMode": "NORMAL",
                "toolsSpec": tools_spec,
                "languageCode": "zh-CN",
                "userMetadata": {"timeZone": "Asia/Shanghai"},
                "assistSkippingMode": "REQUEST_ASSIST"
            }
        }
        if target_model_id:
            google_payload["streamAssistRequest"]["assistGenerationConfig"] = {"modelId": target_model_id}

        async def response_generator():
            chat_id = f"chatcmpl-{uuid.uuid4()}"
            created = int(time.time())
            full_content = ""
            media_files = []
            
            if body.stream:
                yield f"data: {create_chunk(chat_id, created, body.model, {'role': 'assistant'}, None)}\n\n"

            async with client.stream("POST", "https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetStreamAssist", headers=headers, json=google_payload) as r:
                await picker.report_status(acc['id'], r.status_code)
                if r.status_code != 200:
                    err_content = await r.aread()
                    if body.stream: yield f"data: {json.dumps({'error': f'HTTP {r.status_code}: {err_content.decode()[:50]}'})}\n\n"
                    return

                async for json_obj in parse_json_array_stream_async(r.aiter_lines()):
                    sar = json_obj.get("streamAssistResponse", {})
                    replies = sar.get("answer", {}).get("replies", [])
                    for reply in replies:
                        content_obj = reply.get("groundedContent", {}).get("content", {})
                        text = content_obj.get("text", ""); is_thought = content_obj.get("thought", False)
                        file_info = content_obj.get("file")
                        if file_info and file_info.get("fileId"):
                            fid = file_info["fileId"]; mime = file_info.get("mimeType", "image/png")
                            if (fid, mime) not in media_files: media_files.append((fid, mime))
                        if text:
                            if is_thought:
                                if body.stream: yield f"data: {create_chunk(chat_id, created, body.model, {'reasoning_content': text}, None)}\n\n"
                                else: full_content += f"<think>\n{text}\n</think>\n\n"
                            else:
                                full_content += text
                                if body.stream: yield f"data: {create_chunk(chat_id, created, body.model, {'content': text}, None)}\n\n"

                for fid, mime in media_files:
                    try:
                        dl_url = f"https://biz-discoveryengine.googleapis.com/v1alpha/{session_name}:downloadFile?fileId={fid}&alt=media"
                        dl_resp = await client.get(dl_url, headers=headers, follow_redirects=True, timeout=60.0)
                        if dl_resp.status_code == 200:
                            b64 = base64.b64encode(dl_resp.content).decode("utf-8")
                            media_mkd = f"\n\n<video src='data:{mime};base64,{b64}' controls></video>\n\n" if mime.startswith("video/") else f"\n\n![Generated Image](data:{mime};base64,{b64})\n\n"
                            if body.stream: yield f"data: {create_chunk(chat_id, created, body.model, {'content': media_mkd}, None)}\n\n"
                    except: pass

                if body.stream:
                    yield f"data: {create_chunk(chat_id, created, body.model, {}, 'stop')}\n\n"
                    yield "data: [DONE]\n\n"

        if body.stream:
            return StreamingResponse(response_generator(), media_type="text/event-stream")
        else:
            r = await client.post("https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetStreamAssist", headers=headers, json=google_payload)
            await picker.report_status(acc['id'], r.status_code)
            if r.status_code != 200: raise HTTPException(status_code=r.status_code, detail=f"Error: {r.text[:50]}")
            full_text = ""
            media_files_non_stream = []
            for obj in parse_json_array_stream(r.text.splitlines()):
                replies = obj.get("streamAssistResponse", {}).get("answer", {}).get("replies", [])
                for rep in replies:
                    content_obj = rep.get("groundedContent", {}).get("content", {})
                    file_info = content_obj.get("file")
                    if file_info and file_info.get("fileId"): media_files_non_stream.append((file_info["fileId"], file_info.get("mimeType", "image/png")))
                    text = content_obj.get("text", "")
                    if text:
                        if content_obj.get("thought", False): full_text += f"<think>\n{text}\n</think>\n\n"
                        else: full_text += text
            for fid, mime in media_files_non_stream:
                try:
                    dl_url = f"https://biz-discoveryengine.googleapis.com/v1alpha/{session_name}:downloadFile?fileId={fid}&alt=media"
                    dl_resp = await client.get(dl_url, headers=headers, follow_redirects=True)
                    if dl_resp.status_code == 200:
                        b64 = base64.b64encode(dl_resp.content).decode("utf-8")
                        full_text += f"\n\n<video src='data:{mime};base64,{b64}' controls></video>\n\n" if mime.startswith("video/") else f"\n\n![Generated Image](data:{mime};base64,{b64})\n\n"
                except: pass
            return {"id": f"chatcmpl-{uuid.uuid4()}", "object": "chat.completion", "created": int(time.time()), "model": body.model, "choices": [{"index": 0, "message": {"role": "assistant", "content": full_text}, "finish_reason": "stop"}]}

    except Exception as e:
        logger.error(f"[CHAT] Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
