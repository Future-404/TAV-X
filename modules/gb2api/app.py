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

# 【完全复刻版】全局会话缓存
GLOBAL_SESSION_CACHE = {} # conv_key -> {"account_id": str, "session_name": str, "updated_at": float}
CACHE_MAX_SIZE = 1000
SESSION_LOCKS = {} # conv_key -> asyncio.Lock
cache_lock = asyncio.Lock()
session_locks_lock = asyncio.Lock()

sessions_file = os.path.join(os.path.dirname(__file__), "sessions.json")

def load_sessions():
    global GLOBAL_SESSION_CACHE
    if os.path.exists(sessions_file):
        try:
            with open(sessions_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                now = time.time()
                # 只加载未过期的 Session
                valid_sessions = {k: v for k, v in data.items() if now - v.get('updated_at', 0) < 3600}
                GLOBAL_SESSION_CACHE.update(valid_sessions)
                if valid_sessions:
                    logger.info(f"🔄 从本地恢复了 {len(valid_sessions)} 个活跃对话会话")
        except Exception as e:
            logger.warning(f"读取 sessions.json 失败: {e}")

# 启动时加载历史会话
load_sessions()

def save_sessions():
    """将全局会话缓存同步写入本地 (快速且安全)"""
    try:
        temp_file = sessions_file + ".tmp"
        with open(temp_file, "w", encoding="utf-8") as f:
            json.dump(GLOBAL_SESSION_CACHE, f)
        os.replace(temp_file, sessions_file)
    except Exception as e:
        logger.error(f"[CACHE] 持久化会话失败: {e}")

async def clean_expired_cache():
    """后台任务：每5分钟清理一次过期缓存并持久化到本地"""
    while True:
        await asyncio.sleep(300)
        async with cache_lock:
            now = time.time()
            expired = [k for k, v in GLOBAL_SESSION_CACHE.items() if now - v['updated_at'] > 3600]
            for k in expired:
                del GLOBAL_SESSION_CACHE[k]
            if expired:
                logger.info(f"[CACHE] 自动清理了 {len(expired)} 个过期会话")
            
            save_sessions()

async def ensure_cache_size():
    """LRU 淘汰策略：确保缓存不超过 1000 条"""
    if len(GLOBAL_SESSION_CACHE) > CACHE_MAX_SIZE:
        # 按更新时间排序
        sorted_keys = sorted(GLOBAL_SESSION_CACHE.keys(), key=lambda k: GLOBAL_SESSION_CACHE[k]['updated_at'])
        remove_count = len(sorted_keys) - int(CACHE_MAX_SIZE * 0.8)
        for i in range(remove_count):
            del GLOBAL_SESSION_CACHE[sorted_keys[i]]
        logger.info(f"[CACHE] LRU 策略自动清理了 {remove_count} 个旧会话")

class AccountManager:
    def __init__(self):
        self.accounts = []
        self.lock = asyncio.Lock()
        
    def load_accounts(self, accounts_data):
        self.accounts = []
        for acc in accounts_data:
            acc_data = acc.copy()
            acc_data['cooldown_until'] = acc.get('cooldown_until', 0)
            acc_data['fail_count'] = acc.get('fail_count', 0)
            acc_data['import_time'] = acc.get('import_time', 0)
            acc_data['session_name'] = None
            acc_data['session_expires'] = 0
            
            config = types.SimpleNamespace(
                secure_c_ses=acc['secure_c_ses'],
                host_c_oses=acc.get('host_c_oses', ''),
                csesidx=acc['csesidx'],
                account_id=acc['id']
            )
            
            # 启用 http2=True，模拟真实浏览器连接特征
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
            
    async def get_next(self, account_id=None):
        """支持指定ID获取账号（用于Session复用）"""
        async with self.lock:
            if not self.accounts:
                return None
            
            # 如果指定了账号 ID，直接寻找该账号
            if account_id:
                for a in self.accounts:
                    if a['id'] == account_id:
                        return a
            
            now = time.time()
            available = [a for a in self.accounts if a.get('cooldown_until', 0) <= now]
            
            if not available:
                best_acc = min(self.accounts, key=lambda a: a.get('cooldown_until', 0))
                return best_acc
                
            selected = available[0]
            self.accounts.remove(selected)
            self.accounts.append(selected)
            return selected

    async def report_status(self, email, status_code):
        async with self.lock:
            needs_save = False
            for acc in self.accounts:
                if acc['id'] == email:
                    if status_code == 403:
                        acc['cooldown_until'] = time.time() + 31536000 # 1 年 (永久禁用)
                        acc['status'] = 'banned'
                        needs_save = True
                        logger.error(f"⛔ 账号 {email} 遇到 403 权限错误，疑似被封禁，已自动隔离。")
                    elif status_code == 401:
                        acc['cooldown_until'] = time.time() + 300 # 5 分钟
                        acc['status'] = 'expired'
                        needs_save = True
                        logger.error(f"❌ 账号 {email} 会话 401 失效，进入冷却。")
                    elif status_code == 429:
                        acc['fail_count'] = acc.get('fail_count', 0) + 1
                        # 指数退避：5分钟 -> 10分钟 -> 20分钟 -> 最大 6 小时
                        cooldown = min(300 * (2 ** (acc['fail_count'] - 1)), 21600)
                        acc['cooldown_until'] = time.time() + cooldown
                        needs_save = True
                        logger.warning(f"⏳ 账号 {email} 触发 Google 限流 (第{acc['fail_count']}次)，将冷却 {cooldown} 秒。")
                    elif status_code == 200:
                        if acc.get('fail_count', 0) > 0 or acc.get('cooldown_until', 0) > 0:
                            needs_save = True
                        acc['fail_count'] = 0
                        acc['cooldown_until'] = 0
                        if acc.get('status') in ['banned', 'expired']:
                            acc['status'] = 'valid'
                            needs_save = True
                    break
            
            if needs_save:
                asyncio.create_task(self._async_save_accounts())

    async def _async_save_accounts(self):
        """异步将状态写回 accounts.json，避免阻塞主线程"""
        global ACCOUNTS, last_accounts_mtime
        try:
            # 同步最新状态到全局 ACCOUNTS 列表中
            for acc in self.accounts:
                for orig_acc in ACCOUNTS:
                    if orig_acc['id'] == acc['id']:
                        if 'status' in acc: orig_acc['status'] = acc['status']
                        orig_acc['cooldown_until'] = acc.get('cooldown_until', 0)
                        orig_acc['fail_count'] = acc.get('fail_count', 0)
                        if 'import_time' in acc: orig_acc['import_time'] = acc['import_time']
            
            # 原子写入
            temp_file = accounts_file + ".tmp"
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(ACCOUNTS, f, indent=4, ensure_ascii=False)
            os.replace(temp_file, accounts_file)
            last_accounts_mtime = os.path.getmtime(accounts_file)
            logger.info(f"💾 账号状态已持久化到 accounts.json")
        except Exception as e:
            logger.error(f"持久化 accounts.json 失败: {e}")

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
    from core.google_api import create_google_session, get_common_headers, upload_context_file
    from core.message import build_full_context_text, get_conversation_key, parse_last_message
    from core.jwt import JWTManager
    from util.streaming_parser import parse_json_array_stream_async, parse_json_array_stream
except ImportError as e:
    logger.error(f"核心逻辑导入失败: {e}")

from typing import List, Optional, Union, Any

from pydantic import BaseModel

class Message(BaseModel):
    role: str
    content: Any

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

# 【新增】本地账号状态监控接口 (供 check_accounts.py 调用)
@app.get("/_internal/accounts/status")
async def get_accounts_status():
    async with picker.lock:
        status_list = []
        now = time.time()
        for acc in picker.accounts:
            # 判断状态
            state = "valid"
            if acc.get("cooldown_until", 0) > now + 86400:
                # 冷却时间超过1天通常是 403 永久封禁
                state = "banned"
            elif acc.get("cooldown_until", 0) > now + 60:
                # 冷却时间超过60秒通常是 401 失效
                state = "expired"
            elif acc.get("cooldown_until", 0) > now:
                # 短暂冷却通常是 429 限流
                state = "rate_limited"
                
            status_list.append({
                "id": acc["id"],
                "state": state,
                "cooldown_remaining": max(0, int(acc.get("cooldown_until", 0) - now)),
                "import_time": acc.get("import_time", 0)
            })
        return {"total": len(picker.accounts), "accounts": status_list}

# 定义响应生成器和非流式处理函数
async def response_generator(client, headers, google_payload, acc, session_name, model_name):
    chat_id = f"chatcmpl-{uuid.uuid4()}"
    created = int(time.time())
    full_content = ""
    media_files = []
    
    yield f"data: {create_chunk(chat_id, created, model_name, {'role': 'assistant'}, None)}\n\n"

    async with client.stream("POST", "https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetStreamAssist", headers=headers, json=google_payload, timeout=300.0) as r:
        await picker.report_status(acc['id'], r.status_code)
        if r.status_code != 200:
            err_content = await r.aread()
            yield f"data: {json.dumps({'error': f'HTTP {r.status_code}: {err_content.decode()[:50]}'})}\n\n"
            return

        async for json_obj in parse_json_array_stream_async(r.aiter_lines()):
            # 【新增】处理内联错误 (HTTP 200，但 JSON 中包含报错，如限流)
            if "error" in json_obj:
                err_info = json_obj["error"]
                err_msg = err_info.get("message", "Unknown inline error")
                logger.warning(f"[API] 响应中包含错误: {err_msg}")
                if err_info.get("code") == 429 or "RESOURCE_EXHAUSTED" in err_info.get("status", ""):
                    await picker.report_status(acc['id'], 429)
                raise HTTPException(status_code=502, detail=f"Inline Error: {err_msg}")

            sar = json_obj.get("streamAssistResponse", {})
            answer = sar.get("answer", {})
            
            # 【新增】处理安全审查拦截
            if answer.get("state") == "SKIPPED":
                skip_reasons = answer.get("assistSkippedReasons", [])
                if "CUSTOMER_POLICY_VIOLATION" in skip_reasons:
                    error_text = "\n⚠️ 违反政策\n\n由于您的提示违反了 Google 定义的安全政策（例如包含敏感或违规内容），因此 Gemini 拒绝回复。\n\n请修改提示词后重试。\n"
                    yield f"data: {create_chunk(chat_id, created, model_name, {'content': error_text}, None)}\n\n"
                else:
                    error_text = f"\n⚠️ 响应被跳过\n\n原因: {', '.join(skip_reasons)}\n"
                    yield f"data: {create_chunk(chat_id, created, model_name, {'content': error_text}, None)}\n\n"
                continue

            replies = answer.get("replies", [])
            for reply in replies:
                content_obj = reply.get("groundedContent", {}).get("content", {})
                text = content_obj.get("text", ""); is_thought = content_obj.get("thought", False)
                file_info = content_obj.get("file")
                if file_info and file_info.get("fileId"):
                    fid = file_info["fileId"]; mime = file_info.get("mimeType", "image/png")
                    if (fid, mime) not in media_files: media_files.append((fid, mime))
                if text:
                    if is_thought:
                        yield f"data: {create_chunk(chat_id, created, model_name, {'reasoning_content': text}, None)}\n\n"
                    else:
                        full_content += text
                        yield f"data: {create_chunk(chat_id, created, model_name, {'content': text}, None)}\n\n"

    for fid, mime in media_files:
        try:
            dl_url = f"https://biz-discoveryengine.googleapis.com/v1alpha/{session_name}:downloadFile?fileId={fid}&alt=media"
            dl_resp = await client.get(dl_url, headers=headers, follow_redirects=True, timeout=60.0)
            if dl_resp.status_code == 200:
                b64 = base64.b64encode(dl_resp.content).decode("utf-8")
                media_mkd = f"\n\n<video src='data:{mime};base64,{b64}' controls></video>\n\n" if mime.startswith("video/") else f"\n\n![Generated Image](data:{mime};base64,{b64})\n\n"
                yield f"data: {create_chunk(chat_id, created, model_name, {'content': media_mkd}, None)}\n\n"
        except: pass

    yield f"data: {create_chunk(chat_id, created, model_name, {}, 'stop')}\n\n"
    yield "data: [DONE]\n\n"

async def handle_non_stream(client, headers, google_payload, acc, session_name, model_name):
    r = await client.post("https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetStreamAssist", headers=headers, json=google_payload, timeout=300.0)
    await picker.report_status(acc['id'], r.status_code)
    if r.status_code != 200: raise HTTPException(status_code=r.status_code, detail=f"Error: {r.text[:50]}")
    
    full_text = ""
    media_files_non_stream = []
    for obj in parse_json_array_stream(r.text.splitlines()):
        if "error" in obj:
            err_info = obj["error"]
            err_msg = err_info.get("message", "Unknown inline error")
            logger.warning(f"[API] 响应中包含错误: {err_msg}")
            if err_info.get("code") == 429 or "RESOURCE_EXHAUSTED" in err_info.get("status", ""):
                await picker.report_status(acc['id'], 429)
            raise HTTPException(status_code=502, detail=f"Inline Error: {err_msg}")

        sar = obj.get("streamAssistResponse", {})
        answer = sar.get("answer", {})
        
        if answer.get("state") == "SKIPPED":
            skip_reasons = answer.get("assistSkippedReasons", [])
            if "CUSTOMER_POLICY_VIOLATION" in skip_reasons:
                full_text += "\n⚠️ 违反政策\n\n由于您的提示违反了 Google 定义的安全政策（例如包含敏感或违规内容），因此 Gemini 拒绝回复。\n\n请修改提示词后重试。\n"
            else:
                full_text += f"\n⚠️ 响应被跳过\n\n原因: {', '.join(skip_reasons)}\n"
            continue

        replies = answer.get("replies", [])
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
        
    return {
        "id": f"chatcmpl-{uuid.uuid4()}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model_name,
        "choices": [{"index": 0, "message": {"role": "assistant", "content": full_text}, "finish_reason": "stop"}]
    }

@app.post("/v1/chat/completions")
async def chat_completions(request: Request, body: ChatRequest, authorization: str = Header(None)):
    load_manual_accounts()
    if API_KEY and (not authorization or authorization[7:] != API_KEY):
        raise HTTPException(status_code=401, detail="Invalid API Key")

    conv_key = get_conversation_key([m.model_dump() if hasattr(m, 'model_dump') else dict(m) for m in body.messages], request.client.host)
    
    async with session_locks_lock:
        if conv_key not in SESSION_LOCKS:
            SESSION_LOCKS[conv_key] = asyncio.Lock()
        sess_lock = SESSION_LOCKS[conv_key]

    async def run_with_retry():
        request_id = str(uuid.uuid4())[:8]
        max_retries = min(len(ACCOUNTS), 3)
        last_error = None
        
        # 记录当前请求的消息数量，用于判断是否为“重新生成”或“修改历史”
        current_msg_count = len(body.messages)

        for attempt in range(max_retries):
            async with sess_lock:
                async with cache_lock:
                    cached_sess = GLOBAL_SESSION_CACHE.get(conv_key)
                
                acc = None
                session_name = None
                
                # 【核心逻辑】判断是否需要强制创建新会话
                # 如果当前消息数 <= 缓存记录的消息数，说明用户点击了“重新生成”、“删除了历史”或“修改了前面的对话”。
                # 此时 Google 后端的 Session 记忆已经“脏”了（多出了不需要的对话分支），必须抛弃旧 Session。
                force_new_session = False
                if cached_sess:
                    prev_msg_count = cached_sess.get('last_message_count', 0)
                    if current_msg_count <= prev_msg_count:
                        logger.info(f"[CHAT] 检测到对话回溯或重新生成 (当前{current_msg_count}条 <= 历史{prev_msg_count}条)，强制创建新 Session。")
                        force_new_session = True

                if cached_sess and not force_new_session and (time.time() - cached_sess['updated_at'] < 3600):
                    acc = await picker.get_next(cached_sess['account_id'])
                    if acc:
                        session_name = cached_sess['session_name']
                        async with cache_lock:
                            GLOBAL_SESSION_CACHE[conv_key]['updated_at'] = time.time()
                            GLOBAL_SESSION_CACHE[conv_key]['last_message_count'] = current_msg_count
                            save_sessions()
                    else:
                        async with cache_lock: GLOBAL_SESSION_CACHE.pop(conv_key, None)

                if not acc:
                    acc = await picker.get_next()
                    if not acc: raise HTTPException(status_code=500, detail="No accounts")

                client = acc['client']
                try:
                    jwt = await acc['jwt_mgr'].get(request_id)
                    headers = get_common_headers(jwt, USER_AGENT)
                    
                    is_new_session = False
                    if not session_name:
                        is_new_session = True
                        create_sess_body = {
                            "configId": acc['config_id'],
                            "additionalParams": {"token": "-"},
                            "createSessionRequest": {"session": {"name": "", "displayName": ""}}
                        }
                        r_sess = await client.post("https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetCreateSession", headers=headers, json=create_sess_body)
                        if r_sess.status_code == 200:
                            session_name = r_sess.json().get("session", {}).get("name", "")
                            async with cache_lock:
                                GLOBAL_SESSION_CACHE[conv_key] = {
                                    "account_id": acc['id'], 
                                    "session_name": session_name, 
                                    "updated_at": time.time(),
                                    "last_message_count": current_msg_count
                                }
                                await ensure_cache_size()
                                save_sessions() # 立即持久化新会话
                        else:
                            await picker.report_status(acc['id'], r_sess.status_code)
                            continue

                    last_text, current_files = await parse_last_message(body.messages, client, request_id)
                    file_ids = []
                    if current_files:
                        for f in current_files:
                            fid = await upload_context_file(session_name, f["mime"], f["data"], jwt, acc['config_id'], acc['id'], client, USER_AGENT, request_id)
                            file_ids.append(fid)

                    # 【核心优化】智能上下文截断
                    # 如果是新会话，发送全量历史让模型了解前情提要
                    # 如果是复用旧会话，只发送最新一句话，因为 Google 后端 Session 已经保存了记忆
                    text_to_send = build_full_context_text(body.messages) if is_new_session else last_text
                    
                    # 确保最后有 Assistant: 引导 (仅当发全量历史时需要，如果是单句话，加不加皆可，但为了统一保持加上)
                    if not text_to_send.endswith("Assistant:"):
                        text_to_send += "\n\nAssistant:"

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
                            "query": {"parts": [{"text": text_to_send}]},
                            "filter": "",
                            "fileIds": file_ids,
                            "answerGenerationMode": "NORMAL",
                            "toolsSpec": tools_spec,
                            "languageCode": "zh-CN",
                            "userMetadata": {"timeZone": "Asia/Shanghai"},
                            "assistSkippingMode": "REQUEST_ASSIST"
                        }
                    }
                    if target_model_id: google_payload["streamAssistRequest"]["assistGenerationConfig"] = {"modelId": target_model_id}

                    if body.stream:
                        return response_generator(client, headers, google_payload, acc, session_name, body.model)
                    else:
                        return await handle_non_stream(client, headers, google_payload, acc, session_name, body.model)

                except Exception as e:
                    last_error = e
                    logger.warning(f"[CHAT] 账号 {acc['id']} 失败，重试中...: {e}")
                    await picker.report_status(acc['id'], 500)
                    continue

        raise last_error or HTTPException(status_code=500, detail="All retries failed")

    try:
        if body.stream:
            return StreamingResponse(await run_with_retry(), media_type="text/event-stream")
        else:
            return await run_with_retry()
    except Exception as e:
        logger.exception(f"[CHAT] 致命错误: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(clean_expired_cache())

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
