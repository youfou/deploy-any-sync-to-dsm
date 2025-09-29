# 在群晖 DSM 上部署 AnyType (any-sync)



## 背景



[AnyType](https://anytype.io/) 是一款设计超前、体验优秀的笔记类应用，同时也是开源软件。
我突然注意到官方提供了 Docker Compose 的部署方式 (实际已过去两年…)，于是赶紧行动，过程中踩了些坑，记录下来。

相关链接：
- GitHub Repo: [https://github.com/anyproto/any-sync-dockercompose](https://github.com/anyproto/any-sync-dockercompose)
- Github Wiki: [https://github.com/anyproto/any-sync-dockercompose/wiki](https://github.com/anyproto/any-sync-dockercompose/wiki)



需要特别注意的几个点：
- CPU 最好支持 AVX 指令
- 项目使用 Makefile 来操作，但 DSM 没有 make 命令，而且不建议安装以免影响系统稳定性
- DSM 上的 Docker 存在一些差异，需要特别处理
- 自动生成的 client.yml 存在一些非必要的 URI，需要清理


## 系统要求



**参考**: [https://github.com/anyproto/any-sync-dockercompose/wiki/Minimum-system-requirements](https://github.com/anyproto/any-sync-dockercompose/wiki/Minimum-system-requirements)

- **CPU**: 1Core
- **MEM**: 1Gb
- **Disk**: 5Gb
- **系统**
    - 需要在 DSM 上安装 **Container Manager**
    - CPU 最好支持 AVX 指令，否则需要 [额外处理](https://github.com/anyproto/any-sync-dockercompose/wiki/Troubleshooting-&-FAQ#mongodb-requires-a-cpu-with-avx-support)


以下命令可以快速确认自己的 NAS 是否支持 AVX 指令:
```
# 如果你能在输出中看到高亮的 avx，那么就是支持的
cat /proc/cpuinfo | grep avx
```



## 构建



### 克隆代码

安装目录一般放在 Container Mananger 自动创建的 `docker`  目录下就行。
```shell
cd /volume1/docker/
git clone https://github.com/anyproto/any-sync-dockercompose any-sync
```



### 修改配置

开始构建前，需要先根据自己的需求进行配置，把需要修改的部分统一放在 `.env.override`  文件里。默认配置请见 [.env.default](https://github.com/anyproto/any-sync-dockercompose/blob/main/.env.default) 。一般而言，修改外部访问的域名和端口即可。以下为我的版本，供参考：
```shell
# 监听主机。虽然可以加上局域网 IP，但不建议，因为在外面同时查多个可能会更慢
EXTERNAL_LISTEN_HOSTS="xxxxxx.mydomain.pro"

# 监听端口，默认端口号小于 1024 可能被运营商封锁，我统一在前面加了个 “6”，当然也可以换成其他的，比 1024 大就行。
# 注意这里面有 6 个是 TCP 端口，其余 (QUIC) 是 UDP 端口，后续需要配置端口转发。
ANY_SYNC_NODE_1_PORT=61001
ANY_SYNC_NODE_1_QUIC_PORT=61011
ANY_SYNC_NODE_2_PORT=61002
ANY_SYNC_NODE_2_QUIC_PORT=61012
ANY_SYNC_NODE_3_PORT=61003
ANY_SYNC_NODE_3_QUIC_PORT=61013
ANY_SYNC_COORDINATOR_PORT=61004
ANY_SYNC_COORDINATOR_QUIC_PORT=61014
ANY_SYNC_FILENODE_PORT=61005
ANY_SYNC_FILENODE_QUIC_PORT=61015
ANY_SYNC_CONSENSUSNODE_PORT=61006
ANY_SYNC_CONSENSUSNODE_QUIC_PORT=61016

```



### 构建项目

官方说明里没提需要预先创建挂载目录，但实际上 DSM 里的 Docker Compose 在开始构建时，不会自动将不存在的挂载目录创建为文件夹（与其他常见的 Docker 版本表现不同），所以如果不事先创建好，构建时会失败。
另外，在正式开始构建前，还需要生成配置环境，官方文档里一句 `make start` 就完了，但 DSM 没有 `make`，所以需要自行翻译 `Makefile` 里的命令。
我把这两个步骤以及构建整理成了一个脚本。
```shell
#!/bin/bash

# rm -rf storage etc

mkdir -p ./storage/mongo-1
mkdir -p ./storage/redis
mkdir -p ./storage/minio
mkdir -p ./etc/any-sync-coordinator
mkdir -p ./etc/any-sync-coordinator
mkdir -p ./storage/networkStore/any-sync-coordinator
mkdir -p ./etc/any-sync-filenode
mkdir -p ./storage/networkStore/any-sync-filenode
mkdir -p ./etc/any-sync-node-1
mkdir -p ./storage/any-sync-node-1
mkdir -p ./storage/anyStorage/any-sync-node-1
mkdir -p ./storage/networkStore/any-sync-node-1
mkdir -p ./etc/any-sync-node-2
mkdir -p ./storage/any-sync-node-2
mkdir -p ./storage/anyStorage/any-sync-node-2
mkdir -p ./storage/networkStore/any-sync-node-2
mkdir -p ./etc/any-sync-node-3
mkdir -p ./storage/any-sync-node-3
mkdir -p ./storage/anyStorage/any-sync-node-3
mkdir -p ./storage/networkStore/any-sync-node-3
mkdir -p ./etc/any-sync-consensusnode
mkdir -p ./storage/networkStore/any-sync-consensusnode

sudo docker build --tag generateconfig-env --file Dockerfile-generateconfig-env .
sudo docker run --rm --volume "$(pwd)"/:/code/:Z generateconfig-env

sudo docker compose up --detach --remove-orphans

```
*generateconfig 这步，官方用的是 buildx，但实际上 DSM 中的 Docker 没有 buildx，好在我们也不需要，用普通的 build 就行。*

另外，我直接在 ssh 里用 `docker compose` 命令完成构建，而不是打开 Container Manager 来创建和启动项目。这是因为项目开始运行后，会有部分容器自行结束，导致 Container Manager 会认为运行不完整，甚至可能还会报告“容器意外退出”。 另外，后续的升级维护动作，也会让 Container Manager 认为大量容器以外退出。

整个构建过程需要花费几分钟，根据网络情况和机器性能的差异而不同，请耐心等待。



## 获取客户端配置文件

可能由于涉及的端口太多，官方支持自托管用户登录的方式是提供一个  `client.yml` 的客户端配置文件。
这个文件会在构建完成后被生成，位于安装目录中的 `./etc/client.yml` 。

**请把这个文件保存下来，后续在客户端登录时，请点击角落上的齿轮按钮，选择 “自托管”，然后提供这个配置文件。**

如果你打开这个配置文件，就会发现里面包含一些日常使用中非必要的 URI。
我担心这可能导致客户端进行非必要的请求而影响数据同步的速度，所以通过以下正则表达式对配置文件进行了精简。

```perl
 +- (quic://)?(127\.0\.0\.1|any-sync-(node-\d+|coordinator|filenode|consensusnode)):\d+\n
```

*请注意完整复制，*包括开头的空格。
你可以使用 sublime text，vs code 等代码/文本编辑器，打开 `client.yml`，然后使用上述正则表达式进行搜索，然后替换为空即可。



## 实现远程访问

**参考**: [https://github.com/anyproto/any-sync-dockercompose/wiki/Using-proxy,-VPN,-and-other](https://github.com/anyproto/any-sync-dockercompose/wiki/Using-proxy,-VPN,-and-other)

如果你有公网 IP，那么只要设置好 DDNS，并在路由器上配置好端口转发即可。注意这个项目总共有 12 个端口，其中 6 个是 TCP，其余是 UDP，请注意按类型配置。
如果你的路由器支持在端口转发中配置端口范围 (例如 "61001-61006") 那么只需要分别创建 TCP 和 UDP 两条配置即可（请感谢你的路由器厂商），否则你只好老老实实创建 12 条配置。

反之，如果你没有公网 IP，可以考虑使用 Tailscale 等内网穿透方案，网上有很多这方面的教程，这里就不详细展开讨论了。

有些有经验的朋友可能要问，是需要/可以配置反向代理？答案是不需要/不可以，因为数据同步并不使用标准的 HTTPS 协议，而采用其他加密通讯方式，官方 Wiki 中有[ 提到这](https://github.com/anyproto/any-sync-dockercompose/wiki/Using-proxy,-VPN,-and-other#using-a-proxy)点。



## 自动备份

终于轮到 DSM 的长处发挥作用。我用的是 DSM 官方的 **Hyper Backup** 套件备份整个安装目录。功能简单易用，具体配置按照自己需求即可。
更多细节可以查看 [官方 Wiki 的这个页面](https://github.com/anyproto/any-sync-dockercompose/wiki/Backups)。



## 自动更新

**参考**: [https://github.com/anyproto/any-sync-dockercompose/wiki/Upgrade-Guide](https://github.com/anyproto/any-sync-dockercompose/wiki/Upgrade-Guide)

官方的 Makefile 支持更新操作，可惜我们的 DSM 不支持 make 命令，所以再次翻译成普通脚本。好在我们的 DSM 支持 “**计划任务**”，操作方便，你甚至可以要求在执行完成后将结果发送到你的邮箱。

将以下脚本保存到你喜欢的位置。
```shell
#!/bin/bash

# https://github.com/anyproto/any-sync-dockercompose/wiki/Upgrade-Guide

cd /volume1/docker/any-sync

git fetch -pP 2>&1
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ]; then
    echo "Already up to date."
    exit 0
  fi
fi
git pull --ff-only --prune

# pull
docker compose --progress=quiet pull
# down
docker compose --progress=quiet down --remove-orphans

# upgrade only
# docker system prune --all --volumes

# start
docker build --quiet --tag generateconfig-env --file Dockerfile-generateconfig-env . >/dev/null
docker run --rm --volume "$(pwd)"/:/code/:Z generateconfig-env
docker compose --progress=quiet up --detach --remove-orphans --quiet-pull

```


然后打开 **控制面板** > **计划任务**，点击 “**新增**” 按钮 > **计划的任务** > **用户定义的脚本**。选择使用 **root** 账号，选择具体的执行计划 (我选择在每周日的凌晨3点)，然后在 **任务设置** > **运行命令** 处填写：

```shell
bash /path/to/update.sh

# 例如：
# bash /volume1/docker/any-sync-build-helper/update.sh
```



## 大功告成

感谢你看到这里，希望这篇笔记可以解决你正好遇到的问题（如果有的话），或者让你少踩一些坑。
**感谢 Any，打造了如此优秀的产品，并坚持让它保持自由和开放。**