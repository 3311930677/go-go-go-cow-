# -*- coding: utf-8 -*-
"""诊断简幻欢服务器端口连通性"""
import socket

HOST = "sfe4-connect.simpfun.cn"
PORT = 12699

# DNS
try:
    ip = socket.gethostbyname(HOST)
    print("[DNS] %s -> %s" % (HOST, ip))
except Exception as e:
    print("[DNS] 解析失败:", e)

# UDP 探测（发 ENet CONNECT 初始包：首字节 0xFF 是 ENet protocol 的不合法值，
# 服务器如果在线会回复 ICMP unreachable 或 ENet RESET）
print("\n[UDP] 探测 %s:%d ..." % (HOST, PORT))
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
try:
    s.sendto(b"\xff\x00\x00\x00\x00\x00", (HOST, PORT))
    data, addr = s.recvfrom(1024)
    print("[UDP] 收到回复 %d 字节: %s" % (len(data), data.hex()))
    print("[UDP] 服务器在线！")
except socket.timeout:
    print("[UDP] 超时无回复——服务器可能未启动，或端口不是 12699，或 UDP 被防火墙丢弃")
except ConnectionRefusedError:
    print("[UDP] 连接被拒——端口未监听（服务器没跑起来）")
except Exception as e:
    print("[UDP] 异常:", type(e).__name__, e)
finally:
    s.close()

# TCP 探测（简幻欢有些实例用 TCP 承载）
print("\n[TCP] 探测 %s:%d ..." % (HOST, PORT))
s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s2.settimeout(3)
try:
    s2.connect((HOST, PORT))
    print("[TCP] 连接成功！端口有 TCP 服务在监听")
except socket.timeout:
    print("[TCP] 超时——无 TCP 服务或被防火墙丢弃")
except ConnectionRefusedError:
    print("[TCP] 连接被拒——端口无 TCP 监听")
except Exception as e:
    print("[TCP] 异常:", type(e).__name__, e)
finally:
    s2.close()
