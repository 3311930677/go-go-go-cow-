# -*- coding: utf-8 -*-
"""简幻欢实例 SFTP 探测"""
import paramiko, warnings
warnings.filterwarnings("ignore")

HOST = "sfe4-connect.simpfun.cn"
PORT = 2021
USER = "sfe3399284.2f144ec1"
PASS = "1494408108"

t = paramiko.Transport((HOST, PORT))
t.connect(username=USER, password=PASS)
sftp = paramiko.SFTPClient.from_transport(t)
print("[OK] SFTP 连接成功")

print("当前目录:", sftp.getcwd() or "(默认)")
try:
    print("normalize('.') =", sftp.normalize("."))
except Exception as ex:
    print("normalize 失败:", ex)

def ls(path="."):
    try:
        print("\n=== ls %s ===" % path)
        for a in sftp.listdir_attr(path):
            print("  %10s  %s" % (a.st_size, a.filename))
    except Exception as ex:
        print("  [错误]", ex)

ls(".")
ls("..")

t.close()
print("\n[DONE]")
