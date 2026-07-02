FROM teddysun/xray:latest

# teddysun/xray 基于 alpine,内置 xray 二进制、bash
RUN apk add --no-cache curl openssl coreutils

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/data"]

ENTRYPOINT ["/entrypoint.sh"]
