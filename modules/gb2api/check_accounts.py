import json
import os
import asyncio
import httpx
import time
from datetime import datetime

async def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    accounts_file = os.path.join(base_dir, "accounts.json")
    
    if not os.path.exists(accounts_file):
        print("\n\033[91m未找到账号文件 accounts.json，请先导入账号。\033[0m")
        return

    print("\n" + "="*50)
    print("      ♊ GB2API 本地账号健康监控")
    print("="*50 + "\n")
    
    # 尝试连接本地运行的 GB2API 服务获取状态
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get("http://127.0.0.1:7860/_internal/accounts/status")
            if resp.status_code == 200:
                data = resp.json()
                accounts = data.get("accounts", [])
                
                valid_count = 0
                expired_count = 0
                limit_count = 0
                banned_count = 0
                
                for acc in accounts:
                    state = acc['state']
                    email = acc['id']
                    import_time = acc.get('import_time', 0)
                    
                    # 计算导入时长
                    age_str = ""
                    is_old = False
                    if import_time > 0:
                        age_days = (time.time() - import_time) / 86400
                        if age_days >= 14:
                            is_old = True
                            age_str = f" \033[35m(已导入 {int(age_days)} 天，随时可能过期)\033[0m"
                        else:
                            age_str = f" \033[90m(已导入 {int(age_days)} 天)\033[0m"
                    else:
                        age_str = " \033[90m(较早导入)\033[0m"

                    if state == "valid":
                        valid_count += 1
                        if is_old:
                            print(f"  🔍 账号: {email:<30} \033[93m[ ⚠️ 高危运行中 ]\033[0m{age_str}")
                        else:
                            print(f"  🔍 账号: {email:<30} \033[92m[ ✅ 健康运行中 ]\033[0m{age_str}")
                    elif state == "rate_limited":
                        limit_count += 1
                        remain = acc['cooldown_remaining']
                        if remain > 3600:
                            remain_str = f"{remain // 3600}小时{remain % 3600 // 60}分钟"
                        elif remain > 60:
                            remain_str = f"{remain // 60}分钟{remain % 60}秒"
                        else:
                            remain_str = f"{remain}秒"
                        print(f"  🔍 账号: {email:<30} \033[93m[ ⏳ 触发限流，冷却倒计时 {remain_str} ]\033[0m{age_str}")
                    elif state == "banned":
                        banned_count += 1
                        print(f"  🔍 账号: {email:<30} \033[1;31m[ ⛔ 触发 403 被 Google 封禁隔离 ]\033[0m{age_str}")
                    else:
                        expired_count += 1
                        print(f"  🔍 账号: {email:<30} \033[91m[ ❌ 令牌已失效 (401) ]\033[0m{age_str}")
                
                print("\n" + "-"*60)
                print(f"📊 概览: 共 {len(accounts)} 个 | \033[92m健康: {valid_count}\033[0m | \033[93m限流: {limit_count}\033[0m | \033[91m失效: {expired_count}\033[0m | \033[1;31m封禁: {banned_count}\033[0m")
                print("-" * 60)
                if expired_count > 0 or banned_count > 0:
                    print("\n\033[93m💡 提示: 请针对失效或封禁的账号重新运行 [导入账号] 进行覆盖更新。\033[0m")
                
                print("\n(状态数据基于本地内存缓存，零外部网络交互，安全防风控)")
                print("按任意键返回主菜单...")
                return
    except Exception as e:
        print("\033[93m⚠️ 无法连接到 GB2API 后台服务。\033[0m")
        print("请确保服务正在运行。如果服务已关闭，将退回静态文件检查...\n")
        
    # 如果服务没运行，退回简单的文件计数读取
    try:
        with open(accounts_file, "r") as f:
            accounts = json.load(f)
            print(f"📂 离线状态下检测到 \033[92m{len(accounts)}\033[0m 个已导入账号。")
            print("若要查看实时健康状态，请先启动服务。")
    except:
        print("\033[91m无法读取 accounts.json，文件可能损坏。\033[0m")

    print("\n按任意键返回主菜单...")

if __name__ == "__main__":
    asyncio.run(main())
