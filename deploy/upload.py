# -*- coding: utf-8 -*-
"""上传部署文件到简幻欢实例（覆盖预装 start.sh）"""
import paramiko, warnings, os, stat, sys
warnings.filterwarnings("ignore")

HOST = "sfe4-connect.simpfun.cn"
PORT = 2021
USER = "sfe3399284.2f144ec1"
PASS = "1494408108"

FILES = [
    (r"D:\牛来\deploy\start.sh",                "/start.sh",       0o755),
    (r"D:\牛来\deploy\game.pck",                "/game.pck",       0o644),
    (r"D:\牛来\deploy\godot_server",            "/godot_server",   0o755),
]

t = paramiko.Transport((HOST, PORT))
t.connect(username=USER, password=PASS)
sftp = paramiko.SFTPClient.from_transport(t)
print("[OK] SFTP 连接成功")

for local, remote, mode in FILES:
    if not os.path.exists(local):
        print("[MISS] 本地不存在:", local)
        sys.exit(1)
    size = os.path.getsize(local)
    # 跳过远端已一致（或正在被运行中进程占用）的文件
    try:
        if sftp.stat(remote).st_size == size:
            print("跳过 %s（远端已一致）" % os.path.basename(local))
            continue
    except FileNotFoundError:
        pass  # 远端还没有，正常上传
    print("上传 %s (%.1f MB) -> %s ..." % (os.path.basename(local), size / 1048576, remote))
    sftp.put(local, remote)
    sftp.chmod(remote, mode)
    got = sftp.stat(remote)
    mark = "OK" if got.st_size == size else "!! 大小不一致"
    print("   %s 远端 %d 字节" % (mark, got.st_size))

print("\n=== 远端根目录 ===")
for a in sorted(sftp.listdir_attr("/"), key=lambda x: x.filename):
    print("  %12d  %s" % (a.st_size, a.filename))

t.close()
print("\n[DONE] 上传完成")
