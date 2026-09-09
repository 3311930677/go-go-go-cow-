# -*- coding: utf-8 -*-
"""确认远端三件套状态"""
import paramiko, warnings
warnings.filterwarnings("ignore")

t = paramiko.Transport(("sfe4-connect.simpfun.cn", 2021))
t.connect(username="sfe3399284.2f144ec1", password="1494408108")
sftp = paramiko.SFTPClient.from_transport(t)
print("=== 远端根目录 ===")
for a in sorted(sftp.listdir_attr("/"), key=lambda x: x.filename):
    print("  %12d  %s" % (a.st_size, a.filename))
new_pck = 367928
got = sftp.stat("/game.pck").st_size
print("\ngame.pck 大小校验: 远端 %d / 新版 %d -> %s" % (got, new_pck, "一致" if got == new_pck else "不一致!"))
t.close()
