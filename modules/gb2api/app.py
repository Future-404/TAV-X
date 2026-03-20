import os
import json
import time
import asyncio
import uuid
import logging
import base64
from typing import List, Optional, Union, Dict, Any
from fastapi import FastAPI, HTTPException, Header, Request, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import httpx
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

# 设置日志
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger("gb2api")

# 核心配置
API_KEY = os.getenv("API_KEY", "")
PORT = int(os.getenv("PORT", 7860))
HOST = os.getenv("HOST", "0.0.0.0")
PROXY = os.getenv("http_proxy") or os.getenv("https_proxy") or os.getenv("all_proxy")
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

import types
import httpx

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
            
            # 创建虚拟 config 对象供给 JWTManager 使用
            config = types.SimpleNamespace(
                secure_c_ses=acc['secure_c_ses'],
                host_c_oses=acc.get('host_c_oses', ''),
                csesidx=acc['csesidx'],
                account_id=acc['id']
            )
            
            # 为每个账号创建一个独占的 httpx client 以复用连接
            client = httpx.AsyncClient(proxy=PROXY, verify=False, timeout=30.0)
            
            from core.jwt import JWTManager
            acc_data['jwt_mgr'] = JWTManager(config, client, USER_AGENT)
            
            self.accounts.append(acc_data)
            
    async def get_next(self):
        async with self.lock:
            if not self.accounts:
                return None
            now = time.time()
            available = [a for a in self.accounts if a.get('cooldown_until', 0) <= now]
            if not available:
                best_acc = min(self.accounts, key=lambda a: a.get('cooldown_until', 0))
                logger.warning(f"⚠️ 所有账号冷却中，强制使用: {best_acc['id']}")
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
                        acc['cooldown_until'] = time.time() + 600
                        acc['fail_count'] += 1
                        logger.error(f"❌ 账号 {email} 已失效 (401/403)，冷却 10 分钟。")
                    elif status_code == 429:
                        acc['fail_count'] += 1
                        cd = 30 * acc['fail_count']
                        acc['cooldown_until'] = time.time() + cd
                        logger.warning(f"⏳ 账号 {email} 触发限流 (429)，冷却 {cd} 秒。")
                    elif status_code == 200:
                        acc['fail_count'] = 0
                    break

picker = AccountManager()

def load_manual_accounts():
    global ACCOUNTS, picker, last_accounts_mtime
    env_acc = os.getenv("ACCOUNTS_JSON")
    if env_acc:
        try:
            ACCOUNTS = json.loads(env_acc)
            picker.load_accounts(ACCOUNTS)
            return
        except:
            pass
            
    if os.path.exists(accounts_file):
        try:
            mtime = os.path.getmtime(accounts_file)
            if mtime > last_accounts_mtime:
                with open(accounts_file, "r") as f:
                    ACCOUNTS = json.load(f)
                    picker.load_accounts(ACCOUNTS)
                last_accounts_mtime = mtime
                logger.info(f"🔄 检测到 accounts.json 更新，已热重载 {len(ACCOUNTS)} 个账号！")
        except Exception as e:
            logger.error(f"热重载账号失败: {e}")

load_manual_accounts()

# 导入核心逻辑
try:
    from core.google_api import create_google_session, get_common_headers
    from core.message import build_full_context_text
    from core.jwt import JWTManager
    from util.streaming_parser import parse_json_array_stream_async
except ImportError as e:
    logger.error(f"核心逻辑导入失败: {e}")

# --- Models ---
class Message(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    model: str = "gemini-2.5-flash"
    messages: List[Message]
    stream: bool = False
    temperature: Optional[float] = 0.7

app = FastAPI(title="GB2API (Manual Mode)")

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

@app.get("/health")
async def health_check():
    return {"status": "ok", "accounts_count": len(ACCOUNTS)}

@app.get("/v1/models")
async def list_models():
    models = [
        "gemini-auto",
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-3-flash-preview",
        "gemini-3-pro-preview",
        "gemini-3.1-pro-preview",
        "gemini-imagen",
        "gemini-veo"
    ]
    now = int(time.time())
    data = [{"id": m, "object": "model", "created": now, "owned_by": "google"} for m in models]
    return {"object": "list", "data": data}

@app.post("/v1/chat/completions")
async def chat_completions(request: Request, body: ChatRequest, authorization: str = Header(None)):
    load_manual_accounts()
    if API_KEY and (not authorization or authorization[7:] != API_KEY):
        raise HTTPException(status_code=401, detail="Invalid API Key")

    acc = await picker.get_next()
    if not acc: raise HTTPException(status_code=500, detail="No accounts available or all accounts are in cooldown.")

    request_id = str(uuid.uuid4())[:8]
    logger.info(f"[CHAT] [req_{request_id}] Using account: {acc.get('id')}")

    try:
        # 1. 获取 JWT (使用账号自带的 manager)
        jwt = await acc['jwt_mgr'].get(request_id)
        
        # 2. 构造通用请求头
        headers = get_common_headers(jwt, USER_AGENT)
        
        # 3. 创建真实的 Google Session
        create_sess_body = {
            "configId": acc['config_id'],
            "additionalParams": {"token": "-"},
            "createSessionRequest": {
                "session": {"name": "", "displayName": ""}
            }
        }
        async with httpx.AsyncClient(proxy=PROXY, verify=False, timeout=30.0) as client:
            r_sess = await client.post(
                "https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetCreateSession",
                headers=headers,
                json=create_sess_body
            )
            if r_sess.status_code != 200:
                await picker.report_status(acc['id'], r_sess.status_code)
                raise HTTPException(status_code=r_sess.status_code, detail=f"Failed to create session: {r_sess.text[:100]}")
            session_name = r_sess.json().get("session", {}).get("name", "")

        # 4. 处理虚拟模型与 toolsSpec
        tools_spec = {
            "webGroundingSpec": {},
            "toolRegistry": "default_tool_registry",
        }
        target_model_id = body.model
        
        if body.model == "gemini-imagen":
            tools_spec = {"imageGenerationSpec": {}}
            target_model_id = None
        elif body.model == "gemini-veo":
            tools_spec = {"videoGenerationSpec": {}}
            target_model_id = None
        elif body.model == "gemini-auto":
            target_model_id = None

        google_payload = {
            "configId": acc['config_id'],
            "additionalParams": {"token": "-"},
            "streamAssistRequest": {
                "session": session_name,
                "query": {"parts": [{"text": build_full_context_text(body.messages)}]},
                "answerGenerationMode": "NORMAL",
                "toolsSpec": tools_spec,
                "languageCode": "zh-CN",
                "assistSkippingMode": "REQUEST_ASSIST"
            }
        }
        
        if target_model_id:
            google_payload["streamAssistRequest"]["assistGenerationConfig"] = {
                "modelId": target_model_id
            }

        # 3. 发起请求并处理响应
        async def response_generator():
            chat_id = f"chatcmpl-{uuid.uuid4()}"
            created = int(time.time())
            full_content = ""
            media_files = []
            
            if body.stream:
                yield f"data: {create_chunk(chat_id, created, body.model, {'role': 'assistant'}, None)}\n\n"

            async with httpx.AsyncClient(proxy=PROXY, verify=False, timeout=300.0) as client:
                async with client.stream(
                    "POST", 
                    "https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetStreamAssist",
                    headers=headers, 
                    json=google_payload
                ) as r:
                    await picker.report_status(acc['id'], r.status_code)
                    if r.status_code != 200:
                        err_content = await r.aread()
                        err_msg = f"HTTP {r.status_code}: {err_content.decode()[:100]}"
                        
                        # 识别是否为 Cookie 过期
                        if r.status_code in [401, 403]:
                            logger.error(f"❌ 账号 [ {acc.get('id')} ] Session 已过期!")
                            err_msg = f"账号 {acc.get('id')} 会话已过期，请在 TAV-X 菜单中重新导入该账号。"
                        else:
                            logger.error(f"[API] 请求失败: {err_msg}")

                        if body.stream: 
                            yield f"data: {json.dumps({'error': err_msg})}\n\n"
                        else:
                            raise HTTPException(status_code=r.status_code, detail=err_msg)
                        return

                    async for json_obj in parse_json_array_stream_async(r.aiter_lines()):
                        # 提取文本内容
                        sar = json_obj.get("streamAssistResponse", {})
                        replies = sar.get("answer", {}).get("replies", [])
                        for reply in replies:
                            content_obj = reply.get("groundedContent", {}).get("content", {})
                            text = content_obj.get("text", "")
                            is_thought = content_obj.get("thought", False)
                            
                            # 提取图片/视频
                            file_info = content_obj.get("file")
                            if file_info and file_info.get("fileId"):
                                fid = file_info["fileId"]
                                mime = file_info.get("mimeType", "image/png")
                                if (fid, mime) not in media_files:
                                    media_files.append((fid, mime))
                                    
                            if text:
                                if is_thought:
                                    if body.stream:
                                        yield f"data: {create_chunk(chat_id, created, body.model, {'reasoning_content': text}, None)}\n\n"
                                    else:
                                        full_content += f"<think>\n{text}\n</think>\n\n"
                                else:
                                    full_content += text
                                    if body.stream:
                                        yield f"data: {create_chunk(chat_id, created, body.model, {'content': text}, None)}\n\n"

                # 流结束，处理媒体下载
                for idx, (fid, mime) in enumerate(media_files):
                    try:
                        logger.info(f"[MEDIA] 正在下载生成的媒体文件: {fid[:8]}...")
                        dl_url = f"https://biz-discoveryengine.googleapis.com/v1alpha/{session_name}:downloadFile?fileId={fid}&alt=media"
                        dl_resp = await client.get(dl_url, headers=headers, follow_redirects=True, timeout=120.0)
                        dl_resp.raise_for_status()
                        b64_data = base64.b64encode(dl_resp.content).decode("utf-8")
                        
                        if mime.startswith("video/"):
                            media_mkd = f"\n\n<video src='data:{mime};base64,{b64_data}' controls></video>\n\n"
                        else:
                            media_mkd = f"\n\n![Generated Image](data:{mime};base64,{b64_data})\n\n"
                            
                        full_content += media_mkd
                        if body.stream:
                            yield f"data: {create_chunk(chat_id, created, body.model, {'content': media_mkd}, None)}\n\n"
                    except Exception as e:
                        err_msg = f"\n\n> ⚠️ 图片/视频下载失败: {e}\n\n"
                        full_content += err_msg
                        if body.stream:
                            yield f"data: {create_chunk(chat_id, created, body.model, {'content': err_msg}, None)}\n\n"

                if body.stream:
                    yield f"data: {create_chunk(chat_id, created, body.model, {}, 'stop')}\n\n"
                    yield "data: [DONE]\n\n"
                else:
                    # 非流式直接返回最终收集的内容
                    # 此处逻辑在生成器外处理，详见下方返回逻辑
                    pass

        if body.stream:
            return StreamingResponse(response_generator(), media_type="text/event-stream")
        else:
            # 对于非流式，我们需要先耗尽生成器来收集 full_content
            # 或者为了简单起见，这里直接写一个非流式的请求逻辑
            async with httpx.AsyncClient(proxy=PROXY, verify=False, timeout=300.0) as client:
                r = await client.post(
                    "https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetStreamAssist",
                    headers=headers, json=google_payload
                )
                await picker.report_status(acc['id'], r.status_code)
                
                if r.status_code != 200:
                    err_msg = f"HTTP {r.status_code}: {r.text[:100]}"
                    if r.status_code in [401, 403]:
                        err_msg = f"账号 {acc.get('id')} 会话已过期，请重新导入。"
                    raise HTTPException(status_code=r.status_code, detail=err_msg)

                full_text = ""
                media_files_non_stream = []
                async for obj in parse_json_array_stream_async(r.text.splitlines()):
                    replies = obj.get("streamAssistResponse", {}).get("answer", {}).get("replies", [])
                    for rep in replies:
                        content_obj = rep.get("groundedContent", {}).get("content", {})
                        
                        file_info = content_obj.get("file")
                        if file_info and file_info.get("fileId"):
                            fid = file_info["fileId"]
                            mime = file_info.get("mimeType", "image/png")
                            if (fid, mime) not in media_files_non_stream:
                                media_files_non_stream.append((fid, mime))

                        text = content_obj.get("text", "")
                        if text:
                            if content_obj.get("thought", False):
                                full_text += f"<think>\n{text}\n</think>\n\n"
                            else:
                                full_text += text
                                
                for idx, (fid, mime) in enumerate(media_files_non_stream):
                    try:
                        logger.info(f"[MEDIA] 正在下载生成的媒体文件: {fid[:8]}...")
                        dl_url = f"https://biz-discoveryengine.googleapis.com/v1alpha/{session_name}:downloadFile?fileId={fid}&alt=media"
                        dl_resp = await client.get(dl_url, headers=headers, follow_redirects=True, timeout=120.0)
                        dl_resp.raise_for_status()
                        b64_data = base64.b64encode(dl_resp.content).decode("utf-8")
                        
                        if mime.startswith("video/"):
                            full_text += f"\n\n<video src='data:{mime};base64,{b64_data}' controls></video>\n\n"
                        else:
                            full_text += f"\n\n![Generated Image](data:{mime};base64,{b64_data})\n\n"
                    except Exception as e:
                        full_text += f"\n\n> ⚠️ 图片/视频下载失败: {e}\n\n"
                
                return {
                    "id": f"chatcmpl-{uuid.uuid4()}",
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": body.model,
                    "choices": [{"index": 0, "message": {"role": "assistant", "content": full_text}, "finish_reason": "stop"}]
                }

    except Exception as e:
        logger.error(f"[CHAT] Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
