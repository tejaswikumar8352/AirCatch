# Deploying AirCatch Relay to Google Cloud Compute Engine

This guide walks you through deploying the `RemoteRelayServer` to a Google Cloud VM.

## Prerequisites

1.  **Google Cloud Platform (GCP) Account**: [Console Link](https://console.cloud.google.com/)
2.  **gcloud CLI**: Installed on your Mac. [Installation Guide](https://cloud.google.com/sdk/docs/install)
3.  **Project**: A GCP project with billing enabled.

## Step 1: Create a VM Instance

1.  Open the [Compute Engine -> VM Instances](https://console.cloud.google.com/compute/instances) page.
2.  Click **Create Instance**.
3.  **Configuration**:
    -   **Name**: `aircatch-relay`
    -   **Region**: Choose one close to you (e.g., `us-west1`).
    -   **Machine type**: `e2-micro` (Free tier eligible) or `e2-small`.
    -   **Boot disk**: Select "Container Optimized OS" (COS) for easy Docker deployment, OR standard "Debian"/"Ubuntu".
        -   *Recommendation*: **Ubuntu 22.04 LTS** (Standard, easy to use).
    -   **Firewall**: Check **Allow HTTP traffic** and **Allow HTTPS traffic**.
4.  **Advanced Options -> Networking**:
    -   We need to open port `8080`. You can do this later via VPC Firewall rules, or rely on the script below if you tag the instance properly (e.g., `http-server`).
5.  Click **Create**.

## Step 2: Configure Firewall

By default, only ports 80 and 443 are allowed. Use the following `gcloud` command (or UI) to open port 8080:

```bash
gcloud compute firewall-rules create allow-aircatch-8080 \
    --allow tcp:8080 \
    --target-tags http-server,https-server \
    --description "Allow AirCatch Relay traffic"
```

*Ensure your VM has the `http-server` tag (it usually does if you checked "Allow HTTP" during creation).*

## Step 3: Deploy Code

I have created a helper script `deploy_gce.sh` in this folder. You will use it to upload the code and start the server.

### Option A: Automatic Script (if `gcloud` is configured)

1.  Open Terminal in this folder (`RemoteRelayServer`).
2.  Run:
    ```bash
    chmod +x deploy_gce.sh
    ./deploy_gce.sh <YOUR_VM_NAME> <YOUR_ZONE>
    # Example: ./deploy_gce.sh aircatch-relay us-west1-b
    ```

### Option B: Manual Steps (via SSH)

1.  **Zip the code**:
    ```bash
    zip -r relay.zip . -x "node_modules/*"
    ```
2.  **Upload**:
    ```bash
    gcloud compute scp relay.zip teja@aircatch-relay:~/relay.zip --zone=us-west1-b
    ```
3.  **SSH into VM**:
    ```bash
    gcloud compute ssh aircatch-relay --zone=us-west1-b
    ```
4.  **Setup & Run (Inside VM)**:
    ```bash
    # Install Docker & Unzip (if using Ubuntu)
    sudo apt-get update && sudo apt-get install -y docker.io unzip
    
    # Setup
    mkdir -p aircatch-relay
    mv relay.zip aircatch-relay/
    cd aircatch-relay
    unzip relay.zip
    
    # Build & Run
    sudo docker build -t aircatch-relay .
    sudo docker stop current-relay || true
    sudo docker rm current-relay || true
    sudo docker run -d --restart always -p 8080:8080 --name current-relay aircatch-relay
    
    # Verify
    sudo docker ps
    ```

## Step 4: Verify Deployment

1.  Find your **External IP** from the VM Instances console.
2.  Test the connection from your Mac terminal:
    ```bash
    # Replace <VM_IP> with your actual IP
    curl -i -N \
         -H "Connection: Upgrade" \
         -H "Upgrade: websocket" \
         -H "Host: <VM_IP>:8080" \
         -H "Origin: http://<VM_IP>:8080" \
         http://<VM_IP>:8080/ws
    ```
    *You should see a `101 Switching Protocols` response if successful.*

## Step 5: Update AirCatch Config

User the IP address you obtained to update the configuration.

**Host (Mac):** `AirCatchHost/SharedModels.swift`
**Client:** `AirCatchClient/SharedModels.swift`

Change:
`static let remoteRelayURL: String = "ws://<YOUR_VM_IP>:8080/ws"`

*(Note: Use `ws://` instead of `wss://` unless you set up a custom domain and SSL certificate).*
