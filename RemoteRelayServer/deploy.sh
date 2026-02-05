#!/bin/bash
# AirCatch Relay Server EC2 Deployment Script
# Run this on your EC2 instance after SSHing in

set -e

echo "🚀 Deploying AirCatch Relay Server..."

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    sudo apt-get install -y docker.io
    sudo systemctl start docker
    sudo systemctl enable docker
    # Add admin user to docker group
    sudo usermod -aG docker admin
    echo "⚠️  Please log out and back in for Docker group to take effect, then re-run this script"
    exit 0
fi

# Build and run with Docker
echo "🔨 Building Docker image..."
docker build -t aircatch-relay .

# Stop existing container if running
docker stop aircatch-relay 2>/dev/null || true
docker rm aircatch-relay 2>/dev/null || true

# Run container
echo "▶️  Starting relay server..."
docker run -d \
    --name aircatch-relay \
    --restart unless-stopped \
    -p 8080:8080 \
    aircatch-relay

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Ensure security group allows inbound TCP on port 8080"
echo "   2. Get your EC2 public IP: curl http://169.254.169.254/latest/meta-data/public-ipv4"
echo "   3. Use ws://<EC2-IP>:8080 in AirCatch apps"
echo ""
echo "🔍 View logs: docker logs -f aircatch-relay"
echo "🔍 Health check: curl http://localhost:8080/health"
