#!/bin/bash
#
# Script to run Consul agent and Registrator services on the ECS cluster node
#
# (C) Copyright 2018 Opsgang.io, Martin Dobrev
#
################################################################################
set -xe

echo ECS_CLUSTER=${ecs_cluster_name} >> /etc/ecs/ecs.config
echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
echo ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=1h >> /etc/ecs/ecs.config
echo ECS_IMAGE_CLEANUP_INTERVAL=10m >> /etc/ecs/ecs.config


# Start Consul Agent container
docker run -d \
  --name=consul \
  --net=host \
  --restart=on-failure \
  -v /opt/consul/data:/consul/data \
  consul:${consul_version} \
    agent \
    -bind=$(hostname -i) \
    -client=$(hostname -i) \
    -datacenter=${aws_region} \
    -retry-join='provider=aws region=${aws_region} addr_type=private_v4 tag_key=io.opsgang.consul:clusters:nodes tag_value=${consul_cluster_name}'

# Start Registrator container
docker run -d \
    --name=registrator \
    --net=host \
    --restart=on-failure \
    --volume=/var/run/docker.sock:/tmp/docker.sock \
    gliderlabs/registrator:latest \
      -cleanup=true \
      -ip=$(hostname -i) \
      -retry-attempts=-1 \
      -retry-interval=2000 \
      -ttl=90 \
      -ttl-refresh=30 \
      consul://$(hostname -i):8500
