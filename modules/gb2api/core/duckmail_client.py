import os
import random
import string
import time
from typing import Optional

import requests

from core.mail_utils import extract_verification_code
from core.proxy_utils import request_with_proxy_fallback


class DuckMailClient:
    """DuckMail客户端"""

    def __init__(
        self,
        base_url: str = "https://api.duckmail.sbs",
        proxy: str = "",
        verify_ssl: bool = True,
        api_key: str = "",
        log_callback=None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.verify_ssl = verify_ssl
        self.proxies = {"http": proxy, "https": proxy} if proxy else None
        self.api_key = api_key.strip()
        self.log_callback = log_callback

        self.email: Optional[str] = None
        self.password: Optional[str] = None
        self.account_id: Optional[str] = None
        self.token: Optional[str] = None

    def set_credentials(self, email: str, password: str) -> None:
        self.email = email
        self.password = password

    def _request(self, method: str, url: str, **kwargs) -> requests.Response:
        """发送请求并打印详细日志"""
        headers = kwargs.pop("headers", None) or {}
        if self.api_key and "Authorization" not in headers:
            headers["Authorization"] = f"Bearer {self.api_key}"
        kwargs["headers"] = headers
        self._log("info", f"📤 发送 {method} 请求: {url}")
        if "json" in kwargs:
            self._log("info", f"📦 请求体: {kwargs['json']}")

        try:
            res = request_with_proxy_fallback(
                requests.request,
                method,
                url,
                proxies=self.proxies,
                verify=self.verify_ssl,
                timeout=kwargs.pop("timeout", 15),
                **kwargs,
            )
            self._log("info", f"📥 收到响应: HTTP {res.status_code}")
            log_body = os.getenv("DUCKMAIL_LOG_BODY", "").strip().lower() in ("1", "true", "yes", "y", "on")
            if res.content and (log_body or res.status_code >= 400):
                try:
                    self._log("info", f"📄 响应内容: {res.text[:500]}")
                except Exception:
                    pass
            return res
        except Exception as e:
            self._log("error", f"❌ 网络请求失败: {e}")
            raise

    def register_account(self, domain: Optional[str] = None) -> bool:
        """注册新邮箱账号"""
        # 获取域名
        if not domain:
            self._log("info", "🔍 正在获取可用域名...")
            domain = self._get_domain()
        self._log("info", f"📧 使用域名: {domain}")

        # 生成随机邮箱和密码
        rand = "".join(random.choices(string.ascii_lowercase + string.digits, k=10))
        timestamp = str(int(time.time()))[-4:]
        self.email = f"t{timestamp}{rand}@{domain}"
        self.password = f"Pwd{rand}{timestamp}"
        self._log("info", f"🎲 生成邮箱: {self.email}")
        self._log("info", f"🔑 生成密码: {self.password}")

        try:
            self._log("info", "📤 正在向 DuckMail 发送注册请求...")
            res = self._request(
                "POST",
                f"{self.base_url}/accounts",
                json={"address": self.email, "password": self.password},
            )
            if res.status_code in (200, 201):
                data = res.json() if res.content else {}
                self.account_id = data.get("id")
                self._log("info", f"✅ DuckMail 注册成功，账户ID: {self.account_id}")
                return True
            else:
                self._log("error", f"❌ DuckMail 注册失败: HTTP {res.status_code}")
        except Exception as e:
            self._log("error", f"❌ DuckMail 注册异常: {e}")
            return False

        self._log("error", "❌ DuckMail 注册失败")
        return False

    def login(self) -> bool:
        """登录获取token"""
        if not self.email or not self.password:
            self._log("error", "❌ 邮箱或密码未设置")
            return False

        try:
            self._log("info", f"🔐 正在登录 DuckMail: {self.email}")
            res = self._request(
                "POST",
                f"{self.base_url}/token",
                json={"address": self.email, "password": self.password},
            )
            if res.status_code == 200:
                data = res.json() if res.content else {}
                token = data.get("token")
                if token:
                    self.token = token
                    self._log("info", f"✅ DuckMail 登录成功，Token: {token[:20]}...")
                    return True
                else:
                    self._log("error", "❌ 响应中未找到 Token")
            else:
                self._log("error", f"❌ DuckMail 登录失败: HTTP {res.status_code}")
        except Exception as e:
            self._log("error", f"❌ DuckMail 登录异常: {e}")
            return False

        self._log("error", "❌ DuckMail 登录失败")
        return False

    def fetch_verification_code(self, since_time=None) -> Optional[str]:
        """获取验证码"""
        if not self.token:
            self._log("info", "🔐 Token 不存在，尝试重新登录...")
            if not self.login():
                self._log("error", "❌ 登录失败，无法获取验证码")
                return None

        try:
            self._log("info", "📬 正在拉取邮件列表...")
            # 获取邮件列表
            res = self._request(
                "GET",
                f"{self.base_url}/messages",
                headers={"Authorization": f"Bearer {self.token}"},
            )

            if res.status_code != 200:
                self._log("error", f"❌ 获取邮件列表失败: HTTP {res.status_code}")
                return None

            data = res.json() if res.content else {}
            messages = data.get("hydra:member", [])

            if not messages:
                self._log("info", "📭 邮箱为空，暂无邮件")
                return None

            self._log("info", f"📨 收到 {len(messages)} 封邮件，开始检查验证码...")

            from datetime import datetime
            import re

            def _parse_message_time(msg_obj) -> Optional[datetime]:
                created_at = msg_obj.get("createdAt")
                if created_at is None:
                    return None

                if isinstance(created_at, (int, float)):
                    timestamp = float(created_at)
                    if timestamp > 1e12:
                        timestamp = timestamp / 1000.0
                    return datetime.fromtimestamp(timestamp).astimezone().replace(tzinfo=None)

                if isinstance(created_at, str):
                    raw = created_at.strip()
                    if not raw:
                        return None
                    if raw.isdigit():
                        timestamp = float(raw)
                        if timestamp > 1e12:
                            timestamp = timestamp / 1000.0
                        return datetime.fromtimestamp(timestamp).astimezone().replace(tzinfo=None)

                    # 截断纳秒到微秒（fromisoformat 只支持6位小数）
                    raw = re.sub(r"(\.\d{6})\d+", r"\1", raw)
                    return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone().replace(tzinfo=None)

                return None

            # 按时间倒序，优先检查最新邮件
            messages_with_time = [(msg, _parse_message_time(msg)) for msg in messages]
            if any(item[1] is not None for item in messages_with_time):
                messages_with_time.sort(key=lambda item: item[1] or datetime.min, reverse=True)
                messages = [item[0] for item in messages_with_time]

            # 遍历邮件，过滤时间
            for idx, msg in enumerate(messages, 1):
                msg_id = msg.get("id")
                if not msg_id:
                    continue

                # 时间过滤
                if since_time:
                    msg_time = _parse_message_time(msg)
                    if msg_time and msg_time < since_time:
                        continue

                self._log("info", f"🔍 正在读取邮件 {idx}/{len(messages)} (ID: {msg_id[:10]}...)")
                detail = self._request(
                    "GET",
                    f"{self.base_url}/messages/{msg_id}",
                    headers={"Authorization": f"Bearer {self.token}"},
                )

                if detail.status_code != 200:
                    self._log("warning", f"⚠️ 读取邮件详情失败: HTTP {detail.status_code}")
                    continue

                payload = detail.json() if detail.content else {}

                # 获取邮件内容
                text_content = payload.get("text") or ""
                html_content = payload.get("html") or ""

                if isinstance(html_content, list):
                    html_content = "".join(str(item) for item in html_content)
                if isinstance(text_content, list):
                    text_content = "".join(str(item) for item in text_content)

                content = text_content + html_content
                self._log("info", f"📄 邮件内容预览: {content[:200]}...")

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
        since_time=None,
    ) -> Optional[str]:
        """轮询获取验证码"""
        if not self.token:
            self._log("info", "🔐 Token 不存在，尝试登录...")
            if not self.login():
                self._log("error", "❌ 登录失败，无法轮询验证码")
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

    def _get_domain(self) -> str:
        """获取可用域名"""
        try:
            res = self._request("GET", f"{self.base_url}/domains")
            if res.status_code == 200:
                data = res.json() if res.content else {}
                members = data.get("hydra:member", [])
                if members:
                    return members[0].get("domain") or "duck.com"
        except Exception:
            pass
        return "duck.com"

    def _log(self, level: str, message: str) -> None:
        if self.log_callback:
            try:
                self.log_callback(level, message)
            except Exception:
                pass
