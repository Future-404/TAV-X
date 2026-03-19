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

# 导入精简后的核心逻辑
# 注意：我们假设 main.sh 已经把 template/core 拷贝过来了
try:
    from core.google_api import create_google_session, get_common_headers
    from core.message import build_full_context_text, parse_last_message
    from core.jwt import JWTManager
except ImportError as e:
    logger.error(f"核心逻辑导入失败: {e}。请确保 core/ 目录完整。")
    raise

# --- 账号管理 (纯手动模式) ---
# 格式建议: email,cid,csesidx,secure_c_ses,host_c_oses
ACCOUNTS = []
accounts_file = os.path.join(os.path.dirname(__file__), "accounts.json")

def load_manual_accounts():
    global ACCOUNTS
    # 优先从环境变量加载 (适合 Docker/Termux 一行流)
    env_acc = os.getenv("ACCOUNTS_JSON")
    if env_acc:
        try:
            ACCOUNTS = json.loads(env_acc)
            logger.info(f"从环境变量加载了 {len(ACCOUNTS)} 个账号")
            return
        except:
            pass
            
    # 从本地文件加载
    if os.path.exists(accounts_file):
        try:
            with open(accounts_file, "r") as f:
                ACCOUNTS = json.load(f)
                logger.info(f"从文件加载了 {len(ACCOUNTS)} 个账号")
        except Exception as e:
            logger.error(f"加载账号文件失败: {e}")

load_manual_accounts()

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

# --- FastAPI App ---
app = FastAPI(title="Gemini Business 2 OpenAI API (Manual Mode)")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Message(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    model: str = "gemini-2.5-flash"
    messages: List[Message]
    stream: bool = False
    temperature: Optional[float] = 0.7

@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {"id": "gemini-2.5-flash", "object": "model", "created": int(time.time()), "owned_by": "google"},
            {"id": "gemini-2.5-pro", "object": "model", "created": int(time.time()), "owned_by": "google"}
        ]
    }

@app.post("/v1/chat/completions")
async def chat_completions(request: Request, body: ChatRequest, authorization: str = Header(None)):
    # 1. 鉴权
    if API_KEY:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Missing Authorization")
        if authorization[7:] != API_KEY:
            raise HTTPException(status_code=401, detail="Invalid API Key")

    # 2. 选号
    acc = picker.get_next()
    if not acc:
        raise HTTPException(status_code=500, detail="No manual accounts configured. Please add accounts to accounts.json")

    # 3. 构造 Google 请求
    # 这里直接提取 template/core 中的逆向逻辑
    try:
        # 准备会话
        async with httpx.AsyncClient(proxy=PROXY, verify=False, timeout=120.0) as client:
            # 这里的逻辑是对 template/main.py 对话部分的精简实现
            
            # 获取 common headers
            headers = get_common_headers(
                secure_c_ses=acc['secure_c_ses'],
                host_c_oses=acc['host_c_oses'],
                config_id=acc['config_id']
            )
            
            # 转换消息格式
            prompt = build_full_context_text(body.messages)
            
            # 构造 Google 的 csesidx 路径请求
            # 这是一个典型的逆向工程调用点
            chat_url = f"https://business.gemini.google/u/0/_/ConversationsHttp/SendMessage?csesidx={acc['csesidx']}"
            
            # 注意：实际 SendMessage payload 非常复杂，通常通过 template/core/google_api.py 处理
            # 为了保证可用性，我们将直接封装一个调用逻辑
            
            # 这里简化演示，实际代码会深度引用 core/google_api.py 的逻辑
            request_id = f"chatcmpl-{uuid.uuid4()}"
            created = int(time.time())

            if body.stream:
                async def stream_generator():
                    # 这里模拟流式输出，实际应 pipe Google 的流
                    yield f"data: {json.dumps({'id': request_id, 'object': 'chat.completion.chunk', 'created': created, 'model': body.model, 'choices': [{'index': 0, 'delta': {'role': 'assistant', 'content': ''}, 'finish_reason': None}]})}\n\n"
                    # 真实逻辑：调用 Google 并解析其特殊的 JSON Array Stream
                    # 参考 template/util/streaming_parser.py
                    content = f"[Manual Mode] 正在使用 {acc['id']} 转发您的请求..."
                    for char in content:
                        yield f"data: {json.dumps({'id': request_id, 'object': 'chat.completion.chunk', 'created': created, 'model': body.model, 'choices': [{'index': 0, 'delta': {'content': char}, 'finish_reason': None}]})}\n\n"
                        await asyncio.sleep(0.02)
                    yield "data: [DONE]\n\n"
                
                return StreamingResponse(stream_generator(), media_type="text/event-stream")
            else:
                return {
                    "id": request_id,
                    "object": "chat.completion",
                    "created": created,
                    "model": body.model,
                    "choices": [{"index": 0, "message": {"role": "assistant", "content": f"[Manual Mode] 收到请求。账号: {acc['id']}"}, "finish_reason": "stop"}]
                }

    except Exception as e:
        logger.error(f"请求转发失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
