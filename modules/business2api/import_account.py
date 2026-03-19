import json
import re
import os
import sys
import time

def parse_url(url):
    cid = re.search(r'/cid/([a-z0-9-]+)', url)
    csesidx = re.search(r'csesidx=(\d+)', url)
    return (cid.group(1) if cid else None, csesidx.group(1) if csesidx else None)

def parse_cookies(cookie_str):
    # 增强正则，允许前后空格和分号
    ses = re.search(r'__Secure-C_SES=([^; \n\t]+)', cookie_str)
    oses = re.search(r'__Host-C_OSES=([^; \n\t]+)', cookie_str)
    return (ses.group(1) if ses else None, oses.group(1) if oses else None)

def main():
    print("\n" + "="*40)
    print("      ♊ Gemini Business 账号导入")
    print("="*40)
    
    try:
        email = input("\n1. 请输入邮箱: ").strip()
        if not email:
            print("❌ 邮箱不能为空")
            time.sleep(3)
            return

        url = input("2. 请输入登录后的完整URL: ").strip()
        cid, csesidx = parse_url(url)
        if not cid or not csesidx:
            print(f"❌ URL 解析失败 (未找到 cid 或 csesidx)\nURL 内容: {url[:50]}...")
            time.sleep(5)
            return

        print("3. 请输入cookie (粘贴整段后，请手动按一次 回车 键): ")
        # 使用 read() 的变体或循环读取，防止缓冲区溢出
        cookie_str = sys.stdin.readline().strip()
        
        ses, oses = parse_cookies(cookie_str)
        if not ses or not oses:
            print("❌ Cookie 解析失败！")
            print("原因: 未在输入中找到 __Secure-C_SES 或 __Host-C_OSES")
            print(f"输入长度: {len(cookie_str)} 字符")
            time.sleep(5)
            return

        account_info = {
            "id": email,
            "config_id": cid,
            "csesidx": csesidx,
            "secure_c_ses": ses,
            "host_c_oses": oses
        }

        # 使用脚本所在目录的绝对路径
        base_dir = os.path.dirname(os.path.abspath(__file__))
        accounts_file = os.path.join(base_dir, "accounts.json")
        
        accounts = []
        if os.path.exists(accounts_file):
            try:
                with open(accounts_file, "r") as f:
                    accounts = json.load(f)
            except Exception as e:
                print(f"⚠️ 读取旧配置失败 (将创建新文件): {e}")
                
        # 覆盖同名账号
        accounts = [acc for acc in accounts if acc.get('id') != email]
        accounts.append(account_info)
        
        with open(accounts_file, "w") as f:
            json.dump(accounts, f, indent=2)
            
        print("\n" + "-"*40)
        print("✅ 导入成功！")
        print(f"账号: {email}")
        print(f"CID: {cid}")
        print("提示: 您现在可以返回主菜单并 [启动服务] 了。")
        print("-"*40)
        time.sleep(3)

    except KeyboardInterrupt:
        print("\n操作已取消")
    except Exception as e:
        print(f"\n❌ 发生未知错误: {e}")
        time.sleep(5)

if __name__ == "__main__":
    main()
