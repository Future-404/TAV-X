import json
import os
import asyncio
import httpx
import time

# 模拟请求头
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

async def check_account(acc):
    email = acc.get("id", "未知邮箱")
    print(f"  🔍 正在验证: {email:<30} ... ", end="", flush=True)
    
    headers = {
        "User-Agent": USER_AGENT,
        "Cookie": f"__Secure-C_SES={acc['secure_c_ses']}; __Host-C_OSES={acc['host_c_oses']}"
    }
    
    # 模拟获取 JWT 的最小化请求
    google_url = "https://biz-discoveryengine.googleapis.com/v1alpha/locations/global/widgetStreamAssist"
    try:
        async with httpx.AsyncClient(timeout=10.0, verify=False) as client:
            # 仅为了观察 HTTP 状态码
            r = await client.post(google_url, headers=headers, json={})
            
            if r.status_code in [401, 403]:
                print("\033[91m[ ❌ 已失效 ]\033[0m")
                return {"id": email, "status": "expired"}
            elif r.status_code in [200, 400]: # 400 说明鉴权过了，只是 payload 不对
                print("\033[92m[ ✅ 有效 ]\033[0m")
                return {"id": email, "status": "valid"}
            else:
                print(f"\033[93m[ ⚠️ 异常: {r.status_code} ]\033[0m")
                return {"id": email, "status": "unknown"}
    except Exception as e:
        print(f"\033[91m[ 🚫 连接超时 ]\033[0m")
        return {"id": email, "status": "error"}

async def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    accounts_file = os.path.join(base_dir, "accounts.json")
    
    if not os.path.exists(accounts_file):
        print("\n\033[91m未找到账号文件 accounts.json，请先导入账号。\033[0m")
        return

    try:
        with open(accounts_file, "r") as f:
            accounts = json.load(f)
    except:
        print("\n\033[91m无法读取 accounts.json，文件损坏或为空。\033[0m")
        return

    if not accounts:
        print("\n\033[93m账号列表为空。\033[0m")
        return

    print("\n" + "="*50)
    print("      ♊ GB2API 账号监控面板")
    print("="*50 + "\n")
    
    valid_count = 0
    expired_count = 0
    
    for acc in accounts:
        res = await check_account(acc)
        if res["status"] == "valid": valid_count += 1
        elif res["status"] == "expired": expired_count += 1
    
    print("\n" + "-"*50)
    print(f"📊 概览: 共 {len(accounts)} 个 | \033[92m有效: {valid_count}\033[0m | \033[91m失效: {expired_count}\033[0m")
    print("-"*50)
    
    if expired_count > 0:
        print("\n\033[93m💡 提示: 请针对失效账号重新运行 [导入账号] 进行覆盖更新。\033[0m")
    
    print("\n按任意键返回主菜单...")
    # 模拟阻塞直到用户按键

if __name__ == "__main__":
    asyncio.run(main())
