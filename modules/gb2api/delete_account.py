import json
import os
import httpx
import asyncio

async def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    accounts_file = os.path.join(base_dir, "accounts.json")
    
    if not os.path.exists(accounts_file):
        print("\n\033[91m未找到账号文件 accounts.json，您的账号池为空。\033[0m")
        return

    try:
        with open(accounts_file, "r", encoding="utf-8") as f:
            local_accounts = json.load(f)
    except:
        print("\n\033[91m无法读取 accounts.json，文件可能损坏。\033[0m")
        return

    if not local_accounts:
        print("\n\033[93m您的账号池当前为空。\033[0m")
        return

    # 尝试获取实时状态
    api_status = {}
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            resp = await client.get("http://127.0.0.1:7860/_internal/accounts/status")
            if resp.status_code == 200:
                data = resp.json()
                for acc in data.get("accounts", []):
                    api_status[acc["id"]] = acc["state"]
    except:
        pass # 服务没开，只用本地数据

    print("\n" + "="*50)
    print("      ♊ GB2API 账号清理管理")
    print("="*50 + "\n")

    print(f"当前共有 \033[92m{len(local_accounts)}\033[0m 个账号：\n")
    
    for i, acc in enumerate(local_accounts):
        email = acc.get("id", "未知")
        # 优先用 API 实时状态，没有的话用 JSON 里的持久化状态，最后默认未知
        state = api_status.get(email) or acc.get("status") or "unknown"
        
        if state == "valid" or state == "unknown":
            state_str = "\033[92m[健康]\033[0m"
        elif state == "rate_limited":
            state_str = "\033[93m[限流]\033[0m"
        elif state == "banned":
            state_str = "\033[1;31m[封禁]\033[0m"
        elif state == "expired":
            state_str = "\033[91m[失效]\033[0m"
        else:
            state_str = "\033[90m[未知]\033[0m"

        print(f"  [{i+1}] {email:<30} {state_str}")

    print("\n" + "-"*50)
    print("操作指南:")
    print("  - 输入数字: 删除单个账号 (如 '1')")
    print("  - 输入多数字: 批量删除多个账号 (如 '1 3 5')")
    print("  - 输入 \033[93mclean\033[0m: 一键清理所有 [失效] 和 [封禁] 账号")
    print("  - 直接回车: 取消并返回主菜单")
    print("-" * 50)

    choice = input("\n请选择您的操作: ").strip().lower()

    if not choice:
        print("\n操作已取消。")
        return

    to_delete_emails = []

    if choice == "clean":
        for acc in local_accounts:
            email = acc.get("id")
            state = api_status.get(email) or acc.get("status") or "unknown"
            if state in ["banned", "expired"]:
                to_delete_emails.append(email)
        
        if not to_delete_emails:
            print("\n✅ 没有发现失效或被封禁的账号，无需清理。")
            time.sleep(1)
            return
    else:
        indices = choice.split()
        for idx_str in indices:
            if idx_str.isdigit():
                idx = int(idx_str) - 1
                if 0 <= idx < len(local_accounts):
                    to_delete_emails.append(local_accounts[idx].get("id"))

    if not to_delete_emails:
        print("\n❌ 输入无效，未匹配到任何可删除账号。")
        return

    # 去重
    to_delete_emails = list(set(to_delete_emails))

    print(f"\n即将删除以下 {len(to_delete_emails)} 个账号：")
    for e in to_delete_emails:
        print(f" - \033[91m{e}\033[0m")
    
    confirm = input("\n确认删除吗？(y/N): ").strip().lower()
    if confirm == 'y':
        new_accounts = [acc for acc in local_accounts if acc.get("id") not in to_delete_emails]
        try:
            with open(accounts_file, "w", encoding="utf-8") as f:
                json.dump(new_accounts, f, indent=4, ensure_ascii=False)
            print(f"\n✅ 成功删除 {len(to_delete_emails)} 个账号！")
            print("💡 提示：修改已保存，后台服务如果正在运行，将会自动热重载生效。")
        except Exception as e:
            print(f"\n❌ 保存文件失败: {e}")
    else:
        print("\n操作已取消。")

if __name__ == "__main__":
    asyncio.run(main())
