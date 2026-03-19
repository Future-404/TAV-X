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
logger = logging.getLogger("business2api")

# 核心配置
API_KEY = os.getenv("API_KEY", "")
PORT = int(os.getenv("PORT", 7860))
HOST = os.getenv("HOST", "0.0.0.0")
PROXY = os.getenv("http_proxy") or os.getenv("https_proxy") or os.getenv("all_proxy")
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 账号管理
ACCOUNTS = []
accounts_file = os.path.join(os.path.dirname(__file__), "accounts.json")

class AccountPicker:
    def __init__(self, accounts):
        self.accounts = accounts
        self.index = 0
    
    def get_next(self):
        if not self.accounts:
            return None
        acc = self.accounts[self.index]
        self.index = (self.index + 1) % len(self.accounts)
        return acc

picker = AccountPicker(ACCOUNTS)

def load_manual_accounts():
    global ACCOUNTS, picker
    env_acc = os.getenv("ACCOUNTS_JSON")
    if env_acc:
        try:
            ACCOUNTS = json.loads(env_acc)
            picker = AccountPicker(ACCOUNTS)
            return
        except:
            pass
            
    if os.path.exists(accounts_file):
        try:
            with open(accounts_file, "r") as f:
                ACCOUNTS = json.load(f)
                picker = AccountPicker(ACCOUNTS)
        except:
            pass

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

app = FastAPI(title="Gemini Business 2 OpenAI API (Manual Mode)")

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
    return {
        "object": "list",
        "data": [{"id": "gemini-2.5-flash", "object": "model", "created": int(time.time()), "owned_by": "google"}]
    }

@app.post("/v1/chat/completions")
async def chat_completions(request: Request, body: ChatRequest, authorization: str = Header(None)):
    if not ACCOUNTS: load_manual_accounts()
    if API_KEY and (not authorization or authorization[7:] != API_KEY):
        raise HTTPException(status_code=401, detail="Invalid API Key")

    acc = picker.get_next()
    if not acc: raise HTTPException(status_code=500, detail="No accounts")

    request_id = str(uuid.uuid4())[:8]
    logger.info(f"[CHAT] [req_{request_id}] Using account: {acc.get('id')}")

    try:
        # 1. 获取 JWT
        jwt_mgr = JWTManager(acc['secure_c_ses'], acc['host_c_oses'], PROXY, USER_AGENT)
        jwt = await jwt_mgr.get_jwt(request_id)
        
        # 2. 构造请求
        headers = get_common_headers(jwt, USER_AGENT)
        google_payload = {
            "configId": acc['config_id'],
            "additionalParams": {"token": "-"},
            "streamAssistRequest": {
                "session": f"projects/-/locations/global/widgets/default_widget/sessions/session-{uuid.uuid4()}",
                "query": {"parts": [{"text": build_full_context_text(body.messages)}]},
                "answerGenerationMode": "NORMAL",
                "assistGenerationConfig": {"modelId": body.model.replace("gemini-", "")},
                "languageCode": "zh-CN",
                "assistSkippingMode": "REQUEST_ASSIST"
            }
        }

        # 3. 发起请求并处理响应
        async def response_generator():
            chat_id = f"chatcmpl-{uuid.uuid4()}"
            created = int(time.time())
            full_content = ""
            
            if body.stream:
                yield f"data: {create_chunk(chat_id, created, body.model, {'role': 'assistant'}, None)}\n\n"

            async with httpx.AsyncClient(proxy=PROXY, verify=False, timeout=300.0) as client:
                async with client.stream(
                    "POST", 
                    "https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetStreamAssist",
                    headers=headers, 
                    json=google_payload
                ) as r:
                    if r.status_code != 200:
                        err = await r.aread()
                        logger.error(f"[API] Error: {err.decode()}")
                        if body.stream: yield f"data: {json.dumps({'error': err.decode()})}\n\n"
                        return

                    async for json_obj in parse_json_array_stream_async(r.aiter_lines()):
                        # 提取文本内容
                        sar = json_obj.get("streamAssistResponse", {})
                        replies = sar.get("answer", {}).get("replies", [])
                        for reply in replies:
                            content = reply.get("text", "")
                            if content:
                                full_content += content
                                if body.stream:
                                    yield f"data: {create_chunk(chat_id, created, body.model, {'content': content}, None)}\n\n"

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
                full_text = ""
                async for obj in parse_json_array_stream_async(r.text.splitlines()):
                    replies = obj.get("streamAssistResponse", {}).get("answer", {}).get("replies", [])
                    for rep in replies:
                        full_text += rep.get("text", "")
                
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
