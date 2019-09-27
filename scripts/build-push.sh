#!/usr/bin/env bash

set -e

echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

docker build -t tiangolo/docker-registry-proxy:latest .

docker push tiangolo/docker-registry-proxy:latest
