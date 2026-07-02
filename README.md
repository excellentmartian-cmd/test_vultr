# VLESS + REALITY 自动化部署(纯IPv6 / 按量计费VPS)

流程: GitHub Actions 构建镜像 → 推送到 GHCR → VPS 拉取运行 → 容器首次启动自动生成
UUID / X25519 密钥对 / ShortID,写入配置并输出 `vless://` 链接到文件。

## 一、GitHub 仓库端

1. 新建一个仓库,把这几个文件放进去:
   ```
   Dockerfile
   entrypoint.sh
   .github/workflows/build.yml
   deploy.sh
   ```
2. `git add . && git commit -m "init" && git push`
3. 推送到 `main` 分支后,Actions 会自动构建并推送镜像到:
   `ghcr.io/<你的用户名>/<仓库名>:latest`

   注意: 仓库的 GHCR 包默认可能是 private,如果 VPS 上 `docker pull` 报权限错误,
   去 GitHub 仓库 → Packages → 对应包 → Package settings → 改成 Public,
   或者在 VPS 上先 `docker login ghcr.io` 用 PAT 登录。

## 二、VPS 端(纯IPv6按小时计费机器)

```bash
# 确认已装 docker
curl -fsSL https://get.docker.com | sh

# 下载 deploy.sh(或直接用 git clone 整个仓库)
curl -o deploy.sh https://raw.githubusercontent.com/你的用户名/你的仓库/main/deploy.sh
chmod +x deploy.sh

# 执行部署,参数: 镜像地址 [端口,默认443] [SNI伪装域名,默认www.microsoft.com]
./deploy.sh ghcr.io/USER/REPO:latest 443 www.microsoft.com
```

脚本会:
- 自动探测本机公网 IPv6(探测失败会让你手动输入)
- `docker pull` 拉取镜像
- 以 `--network host` 模式启动容器(**关键**: 纯IPv6环境下docker默认bridge网络
  的IPv6支持/NAT配置比较麻烦,直接用host网络最省心,容器内xray直接监听宿主机端口)
- 首次启动时容器内 `entrypoint.sh` 自动生成 UUID、X25519 私钥/公钥、ShortID,
  写好 `config.json`,并把最终的 `vless://...` 链接写到 `/opt/vless-reality-data/link.txt`

## 三、拿到链接

```bash
cat /opt/vless-reality-data/link.txt
```

或者部署脚本跑完会直接打印在终端。

其他信息(UUID/私钥/公钥/ShortID等明文)在:
```bash
cat /opt/vless-reality-data/info.env
```

## 四、关于"按小时计费"场景的持久化

`/opt/vless-reality-data` 挂载了容器的 `/data`,只要这个目录还在,
即使容器被删掉重建(比如换镜像版本),`entrypoint.sh` 默认会**复用**里面已有的
`config.json`,不会重新生成一套新的 UUID/密钥 —— 这样你保存过的 `vless://` 链接
不会失效。

如果你想强制换一套新的(比如怀疑泄露了),重新生成:
```bash
docker rm -f vless-reality
rm -rf /opt/vless-reality-data/*
./deploy.sh ghcr.io/USER/REPO:latest
```
或者直接给容器加 `-e FORCE_REGEN=1` 跑一次。

## 五、其他要点

- REALITY 的 `dest`/`SNI` 建议选一个支持 TLS1.3 + H2、访问量大、在你所在网络环境下
  连通性好的域名(如 `www.microsoft.com`、`www.swift.com` 等),避免用小众站点。
- flow 用的是 `xtls-rprx-vision`,客户端(v2rayN / NekoBox / Shadowrocket等)配置时
  要选对应的 flow,否则连不上。
- 如果 VPS 完全没有 IPv4,只能用支持 IPv6 出站的客户端/前置节点中转,这个不是本部署
  脚本能解决的,是链路层面的问题,需要你自己确认客户端网络能直连到这台VPS的IPv6地址。
