#!/bin/bash

# Update the package index
apt-get update -y

# Install Docker
apt-get install docker.io -y

# Start Docker service
systemctl start docker
systemctl enable docker

docker pull shacharavraham/polybot

sleep 60

# Run the frontend container
docker run -d -p 8443:8443 shacharavraham/polybot:latest

