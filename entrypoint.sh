#!/bin/bash
set -e

CONFIG_DIR=/etc/xray
DATA_DIR=/data
mkdir -p "$CONFIG_DIR" "$DATA_DIR"

LINK_FILE="$DATA_DIR/link.txt"
INFO_FILE="$DATA_DIR/info.env"
CONFIG_FILE="$CONFIG_DIR/config.json"
PERSISTED_CONFIG="$DATA_DIR/config.json"

# 如果 /data 里已经有之前生成的配置(容器重建但挂载卷保留),直接复用,
# 除非显式设置 FORCE_REGEN=1 强制重新生成一套新的 uuid/密钥。
if [ -f "$PERSISTED_CONFIG" ] && [ "$FORCE_REGEN" != "1" ]; then
  cp "$PERSISTED_CONFIG" "$CONFIG_FILE"
  echo "[entrypoint] 检测到已有配置,复用之前生成的 UUID/密钥/ShortID。"
else
  echo "[entrypoint] 生成新的 UUID / X25519 密钥对 / ShortID ..."

  UUID=$(cat /proc/sys/kernel/random/uuid)

  KEY_OUTPUT=$(xray x25519)
  # 兼容两种输出格式:
  # 旧版本: "Private key: xxxx" / "Public key: xxxx"
  # 新版本(v25.3.6+): "PrivateKey: xxxx" / "Password: xxxx" (Password 即公钥)
  PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -iE "^Private ?[Kk]ey" | awk '{print $NF}')
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -iE "^Public ?[Kk]ey|^Password" | awk '{print $NF}')

  if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "[entrypoint] 错误: 未能从 xray x25519 输出中解析出密钥,原始输出如下:"
    echo "$KEY_OUTPUT"
    exit 1
  fi

  SHORT_ID=$(openssl rand -hex 8)

  PORT=${VLESS_PORT:-443}
  DEST=${REALITY_DEST:-www.microsoft.com:443}
  SNI=${REALITY_SNI:-www.microsoft.com}
  REMARK=${REMARK:-vless-reality}

  # 优先使用用户显式传入的 SERVER_ADDR(推荐,尤其纯IPv6环境自动探测可能不准)
  if [ -n "$SERVER_ADDR" ]; then
    SERVER_IP="$SERVER_ADDR"
  else
    # 接口返回 JSON: {"ip":"xxxx"},用 grep/sed 提取 ip 字段的值
    IP_RAW=$(curl -s -6 --max-time 5 https://ifconfig.365919.xyz/ || true)
    SERVER_IP=$(echo "$IP_RAW" | grep -oE '"ip"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"ip"[[:space:]]*:[[:space:]]*"([^"]+)"/\1/')
    if [ -z "$SERVER_IP" ]; then
      SERVER_IP="REPLACE_WITH_YOUR_IPV6"
      echo "[entrypoint] 警告: 未能自动探测到公网IPv6地址,请手动设置环境变量 SERVER_ADDR"
    fi
  fi

  cat > "$CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "::",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "flow": "xtls-rprx-vision" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$DEST",
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
EOF

  # 生成 vless:// 链接。IPv6地址需要用中括号包起来
  VLESS_LINK="vless://${UUID}@[${SERVER_IP}]:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${REMARK}"

  echo "$VLESS_LINK" > "$LINK_FILE"

  cat > "$INFO_FILE" <<EOF
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
SERVER_ADDR=$SERVER_IP
PORT=$PORT
SNI=$SNI
DEST=$DEST
EOF

  cp "$CONFIG_FILE" "$PERSISTED_CONFIG"
fi

echo "===================================================="
echo "VLESS+REALITY 链接 (也已写入 $LINK_FILE):"
cat "$LINK_FILE"
echo "===================================================="

exec xray run -config "$CONFIG_FILE"
