"""
Cloudflare Temp Email 临时邮箱客户端

API 文档参考 (基于 Hono 框架，JWT 认证):
- 获取公开配置: GET /open_api/settings
- 创建新邮箱:   POST /api/new_address  body: {name, domain}  → {address, jwt}
- 获取邮件列表: GET /api/mails          Authorization: Bearer {jwt}
- 获取邮件详情: GET /api/mail/:mail_id  Authorization: Bearer {jwt}
"""

import random
import string
import time
from datetime import datetime
from typing import Optional

import requests

from core.mail_utils import extract_verification_code
from core.proxy_utils import request_with_proxy_fallback


class CloudflareMailClient:
    """Cloudflare Temp Email 临时邮箱客户端"""

    def __init__(
        self,
        base_url: str = "",
        proxy: str = "",
        api_key: str = "",
        domain: str = "",
        verify_ssl: bool = True,
        log_callback=None,
    ) -> None:
        self.base_url = (base_url or "").rstrip("/")
        self.proxy_url = (proxy or "").strip()
        self.api_key = (api_key or "").strip()   # x-custom-auth 密码
        self.domain = (domain or "").strip()
        self.verify_ssl = verify_ssl
        self.log_callback = log_callback

        self.email: Optional[str] = None
        self.password: Optional[str] = None   # 兼容接口，存储 JWT token
        self.jwt_token: Optional[str] = None  # 创建地址时返回的 JWT

        self._available_domains: list = []

    # ------------------------------------------------------------------
    # 内部工具
    # ------------------------------------------------------------------

    def _log(self, level: str, message: str) -> None:
        if self.log_callback:
            try:
                self.log_callback(level, message)
            except Exception:
                pass

    def _request(self, method: str, url: str, **kwargs) -> requests.Response:
        headers = kwargs.pop("headers", None) or {}

        # 实例密码认证（admin 路由使用 x-admin-auth）
        if self.api_key and "x-admin-auth" not in {k.lower() for k in headers}:
            headers["x-admin-auth"] = self.api_key

        # 邮件操作时使用 JWT Bearer 认证
        if self.jwt_token and "authorization" not in {k.lower() for k in headers}:
            headers["Authorization"] = f"Bearer {self.jwt_token}"

        kwargs["headers"] = headers

        self._log("info", f"📤 发送 {method} 请求: {url}")
        if "json" in kwargs and kwargs["json"] is not None:
            self._log("info", f"📦 请求体: {kwargs['json']}")

        proxies = {"http": self.proxy_url, "https": self.proxy_url} if self.proxy_url else None

        try:
            res = request_with_proxy_fallback(
                requests.request,
                method,
                url,
                proxies=proxies,
                verify=self.verify_ssl,
                timeout=kwargs.pop("timeout", 30),
                **kwargs,
            )
            self._log("info", f"📥 收到响应: HTTP {res.status_code}")
            if res.content and res.status_code >= 400:
                try:
                    self._log("error", f"📄 响应内容: {res.text[:500]}")
                except Exception:
                    pass
            return res
        except Exception as e:
            self._log("error", f"❌ 网络请求失败: {e}")
            raise

    # ------------------------------------------------------------------
    # 公开接口
    # ------------------------------------------------------------------

    def set_credentials(self, email: str, password: str = "") -> None:
        """设置凭据（兼容接口）。password 存储 JWT token。"""
        self.email = email
        self.password = password
        if password:
            self.jwt_token = password

    def _get_available_domains(self) -> list:
        """GET /open_api/settings 获取可用域名列表"""
        if self._available_domains:
            return self._available_domains

        try:
            res = self._request("GET", f"{self.base_url}/open_api/settings")
            if res.status_code == 200:
                data = res.json() if res.content else {}
                domains = data.get("domains", [])
                if isinstance(domains, list) and domains:
                    self._available_domains = [str(d).strip() for d in domains if d]
                    self._log("info", f"🌐 CFMail 可用域名: {self._available_domains}")
                    return self._available_domains
        except Exception as e:
            self._log("error", f"❌ 获取可用域名失败: {e}")

        return self._available_domains

    def register_account(self, domain: Optional[str] = None) -> bool:
        """POST /api/new_address 创建新邮箱地址"""
        if not self.base_url:
            self._log("error", "❌ cfmail_base_url 未配置")
            return False

        # 确定域名
        selected_domain = domain or self.domain
        if not selected_domain:
            available = self._get_available_domains()
            if available:
                selected_domain = random.choice(available)

        # 生成随机用户名
        rand = "".join(random.choices(string.ascii_lowercase + string.digits, k=10))
        timestamp = str(int(time.time()))[-4:]
        name = f"t{timestamp}{rand}"

        payload = {"name": name}
        if selected_domain:
            payload["domain"] = selected_domain
            self._log("info", f"📧 使用域名: {selected_domain}")

        self._log("info", f"🎲 创建邮箱: {name}")

        try:
            res = self._request("POST", f"{self.base_url}/admin/new_address", json=payload)

            if res.status_code in (200, 201):
                data = res.json() if res.content else {}
                address = data.get("address", "")
                jwt = data.get("jwt", "")

                if address:
                    self.email = address
                    self.jwt_token = jwt
                    self.password = jwt  # 兼容接口
                    self._log("info", f"✅ CFMail 注册成功: {self.email}")
                    return True

            self._log("error", f"❌ CFMail 注册失败: HTTP {res.status_code}")
            return False

        except Exception as e:
            self._log("error", f"❌ CFMail 注册异常: {e}")
            return False

    def login(self) -> bool:
        """无需登录，直接返回 True"""
        return True

    @staticmethod
    def _extract_body_from_raw(raw: str) -> str:
        """从原始邮件中提取正文（text/plain + text/html），跳过 header"""
        if not raw:
            return ""
        import email as _email
        try:
            msg = _email.message_from_string(raw)
            parts = []
            if msg.is_multipart():
                for part in msg.walk():
                    ct = part.get_content_type()
                    if ct in ("text/plain", "text/html"):
                        payload = part.get_payload(decode=True)
                        if payload:
                            charset = part.get_content_charset() or "utf-8"
                            parts.append(payload.decode(charset, errors="replace"))
            else:
                payload = msg.get_payload(decode=True)
                if payload:
                    charset = msg.get_content_charset() or "utf-8"
                    parts.append(payload.decode(charset, errors="replace"))
            return "".join(parts)
        except Exception:
            return ""

    def fetch_verification_code(self, since_time: Optional[datetime] = None) -> Optional[str]:
        """GET /api/mails 获取邮件列表，再 GET /api/mail/:id 获取详情，提取验证码"""
        if not self.jwt_token:
            self._log("error", "❌ 缺少 JWT token，无法获取邮件")
            return None

        try:
            self._log("info", "📬 正在拉取 CFMail 邮件列表...")
            res = self._request("GET", f"{self.base_url}/api/mails", params={"limit": 20, "offset": 0})

            if res.status_code != 200:
                self._log("error", f"❌ 获取邮件列表失败: HTTP {res.status_code}")
                return None

            data = res.json() if res.content else {}
            # 响应格式: {"results": [...], "total": N}
            messages = data.get("results", [])
            if not isinstance(messages, list):
                messages = []

            if not messages:
                self._log("info", "📭 邮箱为空，暂无邮件")
                return None

            self._log("info", f"📨 收到 {len(messages)} 封邮件，开始检查验证码...")

            # 按 id 降序（新邮件优先）
            try:
                messages = sorted(messages, key=lambda m: int(m.get("id") or 0), reverse=True)
            except Exception:
                pass

            for idx, msg in enumerate(messages, 1):
                msg_id = msg.get("id")
                if not msg_id:
                    continue

                # 时间过滤
                if since_time:
                    raw_time = msg.get("created_at") or msg.get("createdAt")
                    if raw_time:
                        try:
                            if isinstance(raw_time, (int, float)):
                                ts = float(raw_time)
                                if ts > 1e12:
                                    ts /= 1000.0
                                msg_time = datetime.fromtimestamp(ts)
                            else:
                                import re
                                raw_time = re.sub(r"(\.\d{6})\d+", r"\1", str(raw_time))
                                # cfmail 的 created_at 是 UTC 无时区标记，显式加 +00:00 再转本地时间
                                if not raw_time.endswith("Z") and "+" not in raw_time and raw_time.count("-") <= 2:
                                    raw_time = raw_time + "+00:00"
                                msg_time = datetime.fromisoformat(raw_time.replace("Z", "+00:00")).astimezone().replace(tzinfo=None)
                            if msg_time < since_time:
                                continue
                        except Exception:
                            pass

                # 列表响应已包含 raw 字段，直接解析正文提取验证码
                raw_in_list = msg.get("raw") or ""
                if raw_in_list:
                    body = self._extract_body_from_raw(raw_in_list)
                    code = extract_verification_code(body)
                    if code:
                        self._log("info", f"✅ 找到验证码: {code}")
                        return code

                # 兜底：尝试从其他摘要字段提取
                summary = (msg.get("subject") or "") + (msg.get("text") or "") + (msg.get("html") or "")
                if summary:
                    code = extract_verification_code(summary)
                    if code:
                        self._log("info", f"✅ 找到验证码: {code}")
                        return code

                # 获取邮件详情
                self._log("info", f"🔍 正在读取邮件 {idx}/{len(messages)} 详情...")
                detail_res = self._request("GET", f"{self.base_url}/api/mail/{msg_id}")

                if detail_res.status_code != 200:
                    self._log("warning", f"⚠️ 读取邮件详情失败: HTTP {detail_res.status_code}")
                    continue

                detail = detail_res.json() if detail_res.content else {}
                content = self._extract_body_from_raw(detail.get("raw") or "")
                if content:
                    code = extract_verification_code(content)
                    if code:
                        self._log("info", f"✅ 找到验证码: {code}")
                        return code
                    else:
                        self._log("info", f"❌ 邮件 {idx} 中未找到验证码")

            self._log("warning", "⚠️ 所有邮件中均未找到验证码")
            return None

        except Exception as e:
            self._log("error", f"❌ 获取验证码异常: {e}")
            return None

    def poll_for_code(
        self,
        timeout: int = 120,
        interval: int = 4,
        since_time: Optional[datetime] = None,
    ) -> Optional[str]:
        """轮询获取验证码"""
        if not self.email:
            return None

        max_retries = max(1, timeout // interval)
        self._log("info", f"⏱️ 开始轮询验证码 (超时 {timeout}秒, 间隔 {interval}秒, 最多 {max_retries} 次)")

        for i in range(1, max_retries + 1):
            self._log("info", f"🔄 第 {i}/{max_retries} 次轮询...")
            code = self.fetch_verification_code(since_time=since_time)
            if code:
                self._log("info", f"🎉 验证码获取成功: {code}")
                return code
            if i < max_retries:
                self._log("info", f"⏳ 等待 {interval} 秒后重试...")
                time.sleep(interval)

        self._log("error", f"⏰ 验证码获取超时 ({timeout}秒)")
        return None
