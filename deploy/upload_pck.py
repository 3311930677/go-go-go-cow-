import paramiko, os

HOST = 'sfe4-connect.simpfun.cn'
PORT = 2021
USER = 'sfe3399284.2f144ec1'
PW = '1494408108'
LOCAL = 'D:/牛来/release/game.pck'
REMOTE = '/game.pck'

t = paramiko.Transport((HOST, PORT))
t.connect(username=USER, password=PW)
sftp = paramiko.SFTPClient.from_transport(t)

loc = os.path.getsize(LOCAL)
sftp.put(LOCAL, REMOTE)
rem = sftp.stat(REMOTE).st_size
ok = 'OK' if loc == rem else 'MISMATCH'
print(f'local={loc} remote={rem} {ok}')
sftp.close()
t.close()
