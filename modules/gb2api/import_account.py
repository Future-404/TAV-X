import json
import re
import os
import sys
import time

def parse_url(url):
    cid = re.search(r'/cid/([a-z0-9-]+)', url)
    csesidx = re.search(r'csesidx=(\d+)', url)
    return (cid.group(1) if cid else None, csesidx.group(1) if csesidx else None)

def smart_parse_cookies(input_str):
    """智能解析 Cookie，支持 JSON 数组、标准 Cookie 字符串和散装格式"""
    ses, oses = None, None
    input_str = input_str.strip()

    # 1. 尝试作为 JSON 解析 (Cookie Tool 常用导出格式)
    if input_str.startswith('[') and input_str.endswith(']'):
        try:
            data = json.loads(input_str)
            for item in data:
                name = item.get('name')
                value = item.get('value')
                if name == '__Secure-C_SES': ses = value
                elif name == '__Host-C_OSES': oses = value
            if ses and oses: return ses, oses
        except:
            pass

    # 2. 尝试作为标准 Cookie 字符串解析 (正则匹配)
    ses_match = re.search(r'__Secure-C_SES=([^; \n\t]+)', input_str)
    oses_match = re.search(r'__Host-C_OSES=([^; \n\t]+)', input_str)
    
    ses = ses_match.group(1) if ses_match else None
    oses = oses_match.group(1) if oses_match else None
    
    return ses, oses

def main():
    print("\n" + "="*50)
    print("      ♊ GB2API 账号快速导入")
    print("="*50)
    print("\n💡 提示：推荐在 Chrome 或安卓[狐猴浏览器]安装")
    print("   [Cookie Tool] 插件，登录后一键复制粘贴即可。")
    
    try:
        email = input("\n1. 请输入邮箱标识: ").strip()
        if not email:
            print("❌ 邮箱不能为空")
            return

        url = input("2. 请输入登录后的完整URL: ").strip()
        cid, csesidx = parse_url(url)
        if not cid or not csesidx:
            print(f"❌ URL 解析失败 (未找到 cid 或 csesidx)")
            return

        print("\n3. 请粘贴 Cookie 内容:")
        print("   (直接粘贴 Cookie Tool 导出的内容，然后按回车):")
        # 增加读取逻辑，支持处理可能的换行 JSON
        cookie_input = ""
        while True:
            line = sys.stdin.readline()
            if not line or line == '\n': break
            cookie_input += line
            # 如果是标准字符串且已包含关键 key，提前结束
            if "__Secure-C_SES=" in line and "__Host-C_OSES=" in line: break
            # 如果是 JSON 数组且检测到闭合，尝试解析
            if cookie_input.strip().startswith('[') and cookie_input.strip().endswith(']'): break

        ses, oses = smart_parse_cookies(cookie_input)
        if not ses or not oses:
            print("\n❌ Cookie 解析失败！")
            print("原因: 未在输入中找到 __Secure-C_SES 或 __Host-C_OSES")
            return

        account_info = {
            "id": email,
            "config_id": cid,
            "csesidx": csesidx,
            "secure_c_ses": ses,
            "host_c_oses": oses
        }

        base_dir = os.path.dirname(os.path.abspath(__file__))
        accounts_file = os.path.join(base_dir, "accounts.json")
        
        accounts = []
        if os.path.exists(accounts_file):
            try:
                with open(accounts_file, "r", encoding="utf-8") as f:
                    accounts = json.load(f)
            except: pass
                
        accounts = [acc for acc in accounts if acc.get('id') != email]
        accounts.append(account_info)
        
        with open(accounts_file, "w", encoding="utf-8") as f:
            json.dump(accounts, f, indent=2)
            
        print("\n" + "-"*50)
        print("✅ 导入成功！")
        print(f"账号: {email}")
        print("提示: 系统已触发热重载，无需重启服务。")
        print("-" * 50)
        time.sleep(2)

    except KeyboardInterrupt:
        print("\n操作已取消")
    except Exception as e:
        print(f"\n❌ 发生未知错误: {e}")

if __name__ == "__main__":
    main()
