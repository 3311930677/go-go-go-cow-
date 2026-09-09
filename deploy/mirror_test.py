# -*- coding: utf-8 -*-
"""测试多个 GitHub 加速镜像的下载速度"""
import urllib.request, time, sys

URL = "https://github.com/godotengine/godot/releases/download/4.6.1-stable/Godot_v4.6.1-stable_export_templates.tpz"
MIRRORS = [
    ("直连 GitHub", URL),
    ("gh-proxy.com", "https://gh-proxy.com/" + URL),
    ("ghfast.top", "https://ghfast.top/" + URL),
    ("mirror.ghproxy.com", "https://mirror.ghproxy.com/" + URL),
]

for name, url in MIRRORS:
    try:
        req = urllib.request.Request(url, headers={"Range": "bytes=0-5242879"})  # 要 5MB
        t0 = time.time()
        with urllib.request.urlopen(req, timeout=15) as r:
            data = r.read(5 * 1024 * 1024)
        dt = time.time() - t0
        speed = len(data) / dt / 1024
        print("%-20s %6.0f KB/s  (HTTP %s)" % (name, speed, r.status))
    except Exception as e:
        print("%-20s 失败: %s" % (name, type(e).__name__))
