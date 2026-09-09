# -*- coding: utf-8 -*-
"""WebSocket 握手探测：直接对公网地址发起 ws:// 握手，看返回什么"""
import socket, ssl, hashlib, base64, os, time

HOST = "sfe4-connect.simpfun.cn"
PORT = 12699
IP = socket.gethostbyname(HOST)

print("目标: %s (%s):%d" % (HOST, IP, PORT))

# 多次重试（面板重启后网关可能晚几秒才挂载转发）
for attempt in range(3):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(8)
    try:
        s.connect((HOST, PORT))
        print("\n[第%d次] TCP 连接成功！发送 WebSocket 握手..." % (attempt + 1))
        key = base64.b64encode(os.urandom(16)).decode()
        req = ("GET / HTTP/1.1\r\n"
               "Host: %s:%d\r\n"
               "Upgrade: websocket\r\n"
               "Connection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\n"
               "Sec-WebSocket-Version: 13\r\n\r\n" % (HOST, PORT, key))
        s.sendall(req.encode())
        resp = s.recv(4096)
        print("握手响应 %d 字节:" % len(resp))
        print(resp.decode("utf-8", "replace")[:600])
        if b"101" in resp.split(b"\r\n")[0]:
            print("\n>>> WebSocket 升级成功！服务器在线且协议正确 <<<")
        break
    except ConnectionRefusedError:
        print("\n[第%d次] TCP 连接被拒（网关没在转发这个端口，或服务器没监听）" % (attempt + 1))
    except socket.timeout:
        print("\n[第%d次] TCP 超时（防火墙丢弃）" % (attempt + 1))
    except Exception as e:
        print("\n[第%d次] 异常: %s %s" % (attempt + 1, type(e).__name__, e))
    finally:
        s.close()
    if attempt < 2:
        print("5 秒后重试...")
        time.sleep(5)
