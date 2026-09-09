# -*- coding: utf-8 -*-
"""远程查看服务器进程与 pck 校验和"""
import paramiko, warnings
warnings.filterwarnings("ignore")

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("sfe4-connect.simpfun.cn", port=2021,
          username="sfe3399284.2f144ec1", password="1494408108",
          timeout=20, allow_agent=False, look_for_keys=False)

def run(cmd):
    _, out, err = c.exec_command(cmd, timeout=20)
    o = out.read().decode("utf-8", "replace").strip()
    e = err.read().decode("utf-8", "replace").strip()
    return o, e

# exec_command 被网关禁用，改试交互式 shell
try:
    chan = c.invoke_shell(term="xterm", width=120, height=40)
    import time
    time.sleep(2)
    chan.recv(65536)  # 丢弃欢迎信息
    chan.send("ps aux | grep -i godot | grep -v grep; echo ---; md5sum /game.pck; echo ---END\n")
    time.sleep(4)
    buf = b""
    while chan.recv_ready():
        buf += chan.recv(65536)
    print(buf.decode("utf-8", "replace"))
    chan.close()
except Exception as ex:
    print("[FAIL] invoke_shell: %s" % ex)

c.close()
print("[DONE]")
