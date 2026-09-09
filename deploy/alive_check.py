# -*- coding: utf-8 -*-
"""容器存活检查：SFTP 能否连上 + 再探一次 TCP"""
import paramiko, socket, warnings, time
warnings.filterwarnings("ignore")

# 1) SFTP 检查（走的是网关 2021）
try:
    t = paramiko.Transport(("sfe4-connect.simpfun.cn", 2021))
    t.banner_timeout = 15.0
    t.connect(username="sfe3399284.2f144ec1", password="1494408108")
    sftp = paramiko.SFTPClient.from_transport(t)
    files = [a.filename for a in sftp.listdir("/")]
    print("[SFTP] 容器在线，根目录:", files)
    t.close()
except Exception as e:
    print("[SFTP] 连接失败:", type(e).__name__, e)

# 2) 再探 TCP 12699（间隔探测，看网关状态是否变化）
for i in range(3):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    try:
        s.connect(("sfe4-connect.simpfun.cn", 12699))
        print("[TCP %d] 连接成功！" % (i + 1))
        s.close()
        break
    except ConnectionRefusedError:
        print("[TCP %d] 拒绝" % (i + 1))
    except socket.timeout:
        print("[TCP %d] 超时" % (i + 1))
    finally:
        try: s.close()
        except: pass
    time.sleep(3)
