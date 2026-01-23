#!/bin/bash
# deploy_gce.sh
# Usage: ./deploy_gce.sh <INSTANCE_NAME> <ZONE>
# Example: ./deploy_gce.sh aircatch-relay us-west1-b

INSTANCE_NAME=$1
ZONE=$2

if [ -z "$INSTANCE_NAME" ] || [ -z "$ZONE" ]; then
    echo "Usage: ./deploy_gce.sh <INSTANCE_NAME> <ZONE>"
    echo "Example: ./deploy_gce.sh aircatch-relay us-west1-b"
    exit 1
fi

echo "Deploying to $INSTANCE_NAME in $ZONE..."

# 1. Zip
echo "Step 1: Zipping files..."
rm -f relay.zip
zip -r relay.zip . -x "node_modules/*" -x ".git/*" -x "deploy_gce.sh"

# 2. Upload
echo "Step 2: Uploading to VM..."
gcloud compute scp relay.zip teja@$INSTANCE_NAME:~/relay.zip --zone=$ZONE

if [ $? -ne 0 ]; then
    echo "Upload failed. Please check your instance name, zone, and ssh keys."
    exit 1
fi

# 3. Remote Execute
echo "Step 3: Configuring and restarting server on VM..."
gcloud compute ssh teja@$INSTANCE_NAME --zone=$ZONE --command "\
    echo 'Installing dependencies...'; \
    if ! command -v docker &> /dev/null; then \
        sudo apt-get update && sudo apt-get install -y docker.io unzip; \
    fi; \
    echo 'Setting up directory...'; \
    mkdir -p aircatch-relay; \
    mv ~/relay.zip ~/aircatch-relay/; \
    cd ~/aircatch-relay; \
    unzip -o relay.zip; \
    echo 'Building Docker image...'; \
    sudo docker build -t aircatch-relay .; \
    echo 'Stopping old containers...'; \
    sudo docker stop caddy || true; \
    sudo docker rm caddy || true; \
    sudo docker stop current-relay || true; \
    sudo docker rm current-relay || true; \
    echo 'Creating Docker network...'; \
    sudo docker network create aircatch-net || true; \
    echo 'Starting App container...'; \
    sudo docker run -d --restart always \
        --network aircatch-net \
        --name current-relay \
        aircatch-relay; \
    echo 'Starting Caddy (SSL)...'; \
    sudo docker run -d --restart always \
        --network aircatch-net \
        -p 80:80 -p 443:443 \
        -v \$(pwd)/Caddyfile:/etc/caddy/Caddyfile \
        -v caddy_data:/data \
        --name caddy \
        caddy:latest; \
    echo 'Cleaning up...'; \
    rm relay.zip; \
    echo 'Deployment Complete. Server running on port 8080.';"

echo "Done!"
