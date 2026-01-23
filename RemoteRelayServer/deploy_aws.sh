#!/bin/bash
# deploy_aws.sh
# Usage: ./deploy_aws.sh <EC2_IP> <PEM_KEY_PATH>
# Example: ./deploy_aws.sh 54.12.34.56 ~/Desktop/aircatch-key.pem

EC2_IP=$1
PEM_KEY=$2

if [ -z "$EC2_IP" ] || [ -z "$PEM_KEY" ]; then
    echo "Usage: ./deploy_aws.sh <EC2_IP> <PEM_KEY_PATH>"
    echo "Example: ./deploy_aws.sh 54.12.34.56 ~/Desktop/aircatch-key.pem"
    exit 1
fi

# Ensure permissions on key are tight (SSH requires this)
chmod 400 "$PEM_KEY"

echo "Deploying to AWS EC2 ($EC2_IP)..."

# 1. Zip
echo "Step 1: Zipping files..."
rm -f relay.zip
zip -r relay.zip . -x "node_modules/*" -x ".git/*" -x "deploy_gce.sh" -x "deploy_aws.sh"

# 2. Upload
echo "Step 2: Uploading to EC2..."
scp -i "$PEM_KEY" -o StrictHostKeyChecking=no relay.zip ubuntu@$EC2_IP:~/relay.zip

if [ $? -ne 0 ]; then
    echo "Upload failed. Please check your IP and Key path."
    exit 1
fi

# 3. Remote Execute
echo "Step 3: Configuring and restarting server on EC2..."
ssh -i "$PEM_KEY" -o StrictHostKeyChecking=no ubuntu@$EC2_IP "\
    echo 'Installing dependencies...'; \
    if ! command -v docker &> /dev/null; then \
        sudo apt-get update && sudo apt-get install -y docker.io unzip; \
        sudo usermod -aG docker ubuntu; \
    fi; \
    echo 'Setting up directory...'; \
    mkdir -p aircatch-relay; \
    mv ~/relay.zip ~/aircatch-relay/; \
    cd ~/aircatch-relay; \
    unzip -o relay.zip; \
    echo 'Building App Image...'; \
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
    echo 'Deployment Complete. Server running on AWS.';"

echo "Done!"
