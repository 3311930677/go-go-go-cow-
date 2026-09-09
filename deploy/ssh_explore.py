# -*- coding: utf-8 -*-
"""简幻欢实例 SSH 探测"""
import paramiko, warnings
warnings.filterwarnings("ignore")

HOST = "sfe4-connect.simpfun.cn"
PORT = 2021
USER = "sfe3399284.2f144ec1"
PASS = "1494408108"

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, port=PORT, username=USER, password=PASS, timeout=20,
          allow_agent=False, look_for_keys=False)
print("[OK] SSH 连接成功: %s:%d" % (HOST, PORT))

def run(cmd):
    _, out, err = c.exec_command(cmd, timeout=20)
    o = out.read().decode("utf-8", "replace").strip()
    e = err.read().decode("utf-8", "replace").strip()
    return o, e

for cmd in [
    "pwd && whoami",
    "ls -la",
    "cat /etc/os-release | head -2",
    "ls -la /home 2>/dev/null | head",
    # 面板通常把分配的游戏端口写在某处，找找
    "ls -la .. 2>/dev/null | head -20",
    "find . -maxdepth 2 -name '*.json' -o -maxdepth 2 -name '*.cfg' -o -maxdepth 2 -name '*.sh' -o -maxdepth 2 -name '*.txt' 2>/dev/null | head -20",
    "env | grep -iE 'port|simpfun|panel' | head",
]:
    o, e = run(cmd)
    print("\n$ %s\n%s" % (cmd, o if o else ("(空) " + ("[err] " + e if e else ""))))

c.close()
print("\n[DONE]")
