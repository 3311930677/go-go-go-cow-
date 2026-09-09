#!/bin/bash
# ============================================
# 牛走 · 联机专用服务器（简幻欢自定义实例）
# 文件布局：game.pck + Godot Linux 运行时 + 本脚本
# ============================================
cd "$(dirname "$0")"

# 端口：优先用面板注入的变量（若有），否则默认 24565
PORT="${SERVER_PORT:-${PORT:-24565}}"

# 诊断信息（面板日志可见，用于确认端口与内存）
echo "==== 牛走 专用服务器 ===="
echo "SERVER_MEMORY=${SERVER_MEMORY:-未设置}"
echo "SERVER_PORT=${SERVER_PORT:-未设置}  PORT=${PORT:-未设置}  使用端口=$PORT"
echo "公网连接地址: play.simpfun.cn:$PORT"
env | grep -iE 'port|mem|server' | grep -v PASSWD || true
echo "=============================="

chmod +x ./godot_server 2>/dev/null

exec ./godot_server --headless --main-pack game.pck \
	res://scenes/server.tscn -- --port=$PORT --event-interval=25
