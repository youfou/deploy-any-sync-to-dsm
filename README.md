# Deploying AnyType (any-sync) on Synology DSM

🌍 English | [简体中文](https://github.com/youfou/deploy-any-sync-to-dsm/blob/main/README_CN.md)



## Background



[AnyType](https://anytype.io/) is a forward-thinking, excellent note-taking app that’s also open source.
I suddenly noticed that the project offers a Docker Compose deployment method (it’s actually been around for two years…), so I jumped on it. I hit a few bumps along the way and wrote them down here.

Related links:

- GitHub Repo: https://github.com/anyproto/any-sync-dockercompose
- GitHub Wiki: https://github.com/anyproto/any-sync-dockercompose/wiki



A few important notes:

- It’s best if your CPU supports the AVX instruction set.
- The project uses a Makefile, but DSM doesn’t have the `make` command, and it’s not recommended to install it (to avoid impacting system stability).
- Docker on DSM behaves a bit differently and needs special handling.
- The auto-generated `client.yml` includes some non-essential URIs that should be cleaned up.



## System Requirements



**Reference**: https://github.com/anyproto/any-sync-dockercompose/wiki/Minimum-system-requirements

- **CPU**: 1 core
- **MEM**: 1 GB
- **Disk**: 5 GB
- **System**
  - Install **Container Manager** on DSM
  - Ideally, your CPU supports AVX; otherwise, you’ll need [extra handling](https://github.com/anyproto/any-sync-dockercompose/wiki/Troubleshooting-&-FAQ#mongodb-requires-a-cpu-with-avx-support)

You can quickly check whether your NAS supports AVX with the following command:

```shell
# If you see avx highlighted in the output, your CPU supports it.
cat /proc/cpuinfo | grep avx
```



## Build



### Clone the repo

Placing it under the `docker` directory that Container Manager auto-creates is fine.

```shell
cd /volume1/docker/
git clone https://github.com/anyproto/any-sync-dockercompose any-sync
```



### Adjust configuration

Before building, customize settings to your needs. Put your changes in `.env.override`. The defaults are in [.env.default](https://github.com/anyproto/any-sync-dockercompose/blob/main/.env.default). In most cases, you only need to change the public domain and ports. Here’s my version for reference:

```shell
# Listening hosts. You could add your LAN IP, but I don’t recommend it,
# because checking multiple ones from outside can be slower.
EXTERNAL_LISTEN_HOSTS="xxxxxx.mydomain.pro"

# Listening ports. Ports under 1024 are often blocked by ISPs. I prefixed them with “6”,
# but any value >1024 is fine.
# Note: Six of these are TCP ports; the rest (QUIC) are UDP ports—you’ll need to set up port forwarding later.
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



### Build the project

The official docs don’t mention pre-creating mount directories, but on DSM, Docker Compose won’t auto-create missing host-side mount paths at build-up time (unlike some other Docker environments). If you don’t create them first, the build will fail.
 Also, before starting the build, you need to generate the config environment. The docs hand-wave this with a simple `make start`, but since DSM has no `make`, we have to translate the Makefile steps ourselves.

I combined those two steps plus the build into one script:

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

*For the `generateconfig` step, the official instructions use `buildx`, but Docker on DSM doesn’t have `buildx`. Fortunately, we don’t need it—`docker build` works fine.*

Also, I run `docker compose` over SSH to create and start the project, rather than using Container Manager’s UI. That’s because once the stack is running, some containers will exit by design, which makes Container Manager think the stack is incomplete and may even report “container exited unexpectedly.” Future upgrades/maintenance will similarly make it look like many containers exited unexpectedly.

The whole process takes a few minutes depending on your network and hardware—please be patient.



## Get the client config file

Because of the large number of ports involved, the official way for self-hosted users to sign in is to provide a `client.yml` configuration file.
This file is generated after the build completes and is located at `./etc/client.yml` in the install directory.

**Make sure to save this file. In the client app, click the gear icon, choose “Self-hosted,” and provide this configuration file.**

If you open the file, you’ll notice it includes some URIs that aren’t necessary for everyday use. I’m concerned these might trigger unnecessary requests and slow down sync, so I trimmed the file with the regex below:

```perl
 +- (quic://)?(127\.0\.0\.1|any-sync-(node-\d+|coordinator|filenode|consensusnode)):\d+\n
```

*Be sure to copy this in full,* including the leading space.
 Use a code/text editor like Sublime Text or VS Code, open `client.yml`, search with the regex above, and replace matches with nothing.



## Enable remote access

**Reference**: https://github.com/anyproto/any-sync-dockercompose/wiki/Using-proxy,-VPN,-and-other

If you have a public IP, set up DDNS and configure port forwarding on your router. Note this project uses 12 ports in total: 6 TCP and the rest UDP—configure each with the correct protocol.
 If your router supports port ranges (e.g., `61001–61006`), then you only need two rules (one TCP, one UDP). Otherwise, you’ll have to create 12 separate rules.

If you don’t have a public IP, consider NAT traversal solutions like Tailscale. There are many tutorials online, so I won’t go into detail here.

Some experienced users may ask whether a reverse proxy is needed/allowed. The answer is **no**, because sync traffic doesn’t use standard HTTPS; it uses other encrypted protocols. The official Wiki [mentions this](https://github.com/anyproto/any-sync-dockercompose/wiki/Using-proxy,-VPN,-and-other#using-a-proxy).



## Automated backups

Here’s where DSM shines. I use Synology’s **Hyper Backup** to back up the entire install directory. It’s simple and effective—configure it as you like.
 For more details, see [this Wiki page](https://github.com/anyproto/any-sync-dockercompose/wiki/Backups).



## Automated updates

**Reference**: https://github.com/anyproto/any-sync-dockercompose/wiki/Upgrade-Guide

The official Makefile supports upgrades, but we don’t have `make` on DSM, so here’s a plain-shell translation. DSM’s **Task Scheduler** makes this easy; you can even have results emailed to you after it runs.

Save the following script wherever you like:

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



Then open **Control Panel > Task Scheduler**, click **Create** > **Scheduled Task** > **User-defined script**. Choose the **root** account, pick your schedule (I run it at 3:00 AM every Sunday), and under **Task Settings > Run command**, enter:

```shell
bash /path/to/update.sh

# For example:
# bash /volume1/docker/any-sync-build-helper/update.sh
```



## All set

Thanks for reading this far! I hope this note solves a problem you’re facing (if any) or helps you avoid a few pitfalls.
**Thanks to Any for building such an outstanding product and keeping it free and open.**