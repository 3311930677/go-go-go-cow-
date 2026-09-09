# -*- coding: utf-8 -*-
"""读取远程 start.sh 内容"""
import paramiko, warnings
warnings.filterwarnings("ignore")

HOST = "sfe4-connect.simpfun.cn"
PORT = 2021
USER = "sfe3399284.2f144ec1"
PASS = "1494408108"

t = paramiko.Transport((HOST, PORT))
t.connect(username=USER, password=PASS)
sftp = paramiko.SFTPClient.from_transport(t)

with sftp.open("/start.sh", "r") as f:
    print(f.read().decode("utf-8", "replace"))

t.close()
