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
