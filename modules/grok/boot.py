#!/usr/bin/env python3
import os
import pty
import sys
import subprocess
import signal
import select
import time
import shlex

# [TAV-X Grok Bootloader v2]
# 作用：在 Termux PRoot 环境下，使用伪终端 (PTY) 启动服务
# 特性：支持信号转发 (SIGTERM)，防止僵尸进程占用端口

host_home = os.environ.get("HOME", "/data/data/com.termux/files/home")
inner_dir = os.environ.get("INNER_DIR")

if not inner_dir:
    cwd = os.getcwd()
    if host_home in cwd:
        inner_dir = cwd.replace(host_home, "/root")
    else:
        inner_dir = "/root/tav_apps/grok"

print(f"🚀 Grok Boot: Host[{host_home}] -> Guest[/root]")
print(f"📂 WorkDir:  Guest[{inner_dir}]")

# 4. 筛选并传递环境变量
env_vars_to_pass = {}
# 默认传递的关键变量
keys_to_pass = {"PORT", "WORKERS", "HOST", "LOG_LEVEL"}
for k, v in os.environ.items():
    if k in keys_to_pass or k.startswith("GROK_"):
        env_vars_to_pass[k] = v

# 构建 export 语句字符串
env_export_str = " ".join([f"export {k}={shlex.quote(v)}" for k, v in env_vars_to_pass.items()])
if env_export_str:
    env_export_str += " &&"

cmd = [
    "proot-distro", "login", "debian",
    "--user", "root",
    "--shared-tmp",
    "--bind", f"{host_home}:/root",
    "--",
    "bash", "-c",
    f"{env_export_str} cd {inner_dir} && source .venv/bin/activate && python3 main.py"
]

# 1. 创建 PTY
master_fd, slave_fd = pty.openpty()

# 2. 启动子进程 (Proot)
proc = subprocess.Popen(
    cmd,
    stdin=slave_fd,
    stdout=slave_fd,
    stderr=slave_fd,
    close_fds=True,
    start_new_session=True # 这一步很关键，创建新会话
)
os.close(slave_fd) # 父进程关闭 slave 句柄

# 3. 注册信号处理 (用于优雅退出)
def signal_handler(sig, frame):
    print(f"\n🛑 Bootloader received signal {sig}. Terminating child...")
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            print("💀 Force killing child...")
            proc.kill()
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

# 4. IO 转发循环
try:
    while proc.poll() is None:
        # 监听 master_fd 的输出 (Proot 的输出)
        r, _, _ = select.select([master_fd], [], [], 1.0)
        if master_fd in r:
            try:
                data = os.read(master_fd, 4096)
                if not data:
                    break # EOF
                sys.stdout.buffer.write(data)
                sys.stdout.flush()
            except OSError:
                break
except Exception as e:
    print(f"⚠️ Loop error: {e}")
finally:
    # 确保子进程被清理
    if proc.poll() is None:
        proc.terminate()
    try:
        os.close(master_fd)
    except:
        pass
    sys.exit(proc.returncode if proc.returncode is not None else 1)