#!/bin/bash
# 在 VPS(纯IPv6、按小时计费)上运行,拉取镜像并启动容器
# 用法: ./deploy.sh ghcr.io/USER/REPO:latest [端口] [SNI]

set -e

IMAGE="${1:?用法: ./deploy.sh <镜像地址> [端口] [SNI]}"
PORT="${2:-443}"
SNI="${3:-www.microsoft.com}"
DATA_DIR="/opt/vless-reality-data"

mkdir -p "$DATA_DIR"

echo "[deploy] 探测本机公网 IPv6 ..."
IP_RAW=$(curl -s -6 --max-time 5 https://ifconfig.365919.xyz/ || true)
SERVER_ADDR=$(echo "$IP_RAW" | grep -oE '"ip"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"ip"[[:space:]]*:[[:space:]]*"([^"]+)"/\1/')
if [ -z "$SERVER_ADDR" ]; then
  echo "[deploy] 自动探测失败,请手动输入本机公网IPv6地址:"
  read -r SERVER_ADDR
fi
echo "[deploy] 使用地址: $SERVER_ADDR"

echo "[deploy] 拉取镜像 $IMAGE ..."
docker pull "$IMAGE"

echo "[deploy] 停止并移除旧容器(如存在)..."
docker rm -f vless-reality 2>/dev/null || true

echo "[deploy] 启动新容器 (host网络模式,规避IPv6下docker NAT问题)..."
docker run -d \
  --name vless-reality \
  --network host \
  --restart unless-stopped \
  -e VLESS_PORT="$PORT" \
  -e REALITY_SNI="$SNI" \
  -e REALITY_DEST="${SNI}:443" \
  -e SERVER_ADDR="$SERVER_ADDR" \
  -v "$DATA_DIR:/data" \
  "$IMAGE"

echo "[deploy] 等待容器生成配置..."
sleep 3

echo "===================================================="
echo "部署完成! 你的 vless:// 链接:"
cat "$DATA_DIR/link.txt"
echo "===================================================="
echo "完整信息见: $DATA_DIR/info.env"
echo "配置文件见: $DATA_DIR/config.json"
echo "查看运行日志: docker logs -f vless-reality"
