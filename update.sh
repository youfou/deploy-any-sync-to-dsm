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
