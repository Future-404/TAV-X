import json
import re
import os
import sys

def parse_url(url):
    cid = re.search(r'/cid/([a-z0-9-]+)', url)
    csesidx = re.search(r'csesidx=(\d+)', url)
    return (cid.group(1) if cid else None, csesidx.group(1) if csesidx else None)

def parse_cookies(cookie_str):
    ses = re.search(r'__Secure-C_SES=([^; ]+)', cookie_str)
    oses = re.search(r'__Host-C_OSES=([^; \n]+)', cookie_str)
    return (ses.group(1) if ses else None, oses.group(1) if oses else None)

def main():
    print("\n--- ♊ Gemini Business 账号导入 ---")
    
    email = input("1. 请输入邮箱: ").strip()
    if not email:
        print("❌ 邮箱不能为空")
        return

    url = input("2. 请输入登录后的完整URL: ").strip()
    cid, csesidx = parse_url(url)
    if not cid or not csesidx:
        print("❌ URL 解析失败，未找到 cid 或 csesidx")
        return

    print("3. 请输入cookie (直接粘贴整段): ")
    # 处理可能的换行或多行输入（如果是从某些终端粘贴）
    cookie_str = sys.stdin.readline().strip()
    # 如果一行没读够（有些插件导出的带换行），可以继续读，但通常插件是一行
    
    ses, oses = parse_cookies(cookie_str)
    if not ses or not oses:
        print("❌ Cookie 解析失败，未找到关键字段 (__Secure-C_SES 或 __Host-C_OSES)")
        return

    account_info = {
        "id": email,
        "config_id": cid,
        "csesidx": csesidx,
        "secure_c_ses": ses,
        "host_c_oses": oses
    }

    accounts_file = "accounts.json"
    accounts = []
    if os.path.exists(accounts_file):
        try:
            with open(accounts_file, "r") as f:
                accounts = json.load(f)
        except:
            pass
            
    # 检查是否已存在（按ID/邮箱覆盖）
    accounts = [acc for acc in accounts if acc['id'] != email]
    accounts.append(account_info)
    
    with open(accounts_file, "w") as f:
        json.dump(accounts, f, indent=2)
        
    print("\n✅ 导入成功！")
    print(f"账号: {email}")
    print(f"CID: {cid}")
    print("-" * 30)

if __name__ == "__main__":
    main()
