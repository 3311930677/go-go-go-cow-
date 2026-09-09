import paramiko, os

HOST = 'sfe4-connect.simpfun.cn'
PORT = 2021
USER = 'sfe3399284.2f144ec1'
PW = '1494408108'

FILES = [
    ('D:/牛来/release/game.pck', '/game.pck'),
    ('D:/牛来/deploy/start.sh', '/start.sh'),
]

t = paramiko.Transport((HOST, PORT))
t.connect(username=USER, password=PW)
sftp = paramiko.SFTPClient.from_transport(t)

for local, remote in FILES:
    loc = os.path.getsize(local)
    sftp.put(local, remote)
    rem = sftp.stat(remote).st_size
    ok = 'OK' if loc == rem else 'MISMATCH!!'
    print(f'{remote}: local={loc} remote={rem} {ok}')

# start.sh 需要可执行权限
sftp.chmod('/start.sh', 0o755)
print('start.sh chmod 755 OK')
sftp.close()
t.close()
