#!/bin/bash

# Oracle Cloud "Sniper" Script
# Tries to launch the AirCatch relay server every 60 seconds until successful.
# Useful for "Out of host capacity" errors in the Always Free tier.

COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaahrlcf5qf3uwbmmupvoaq2nak4pgpzdrzf7dgojrxfxdfzq7xqh3q"
SUBNET_ID="ocid1.subnet.oc1.phx.aaaaaaaaafjnw37jy7ubfuutznanibi3pveva6wxs7fp2lseqfc6vhsfrzla"
IMAGE_ID="ocid1.image.oc1.phx.aaaaaaaagrsiqy75p2vblxtrqn7ttjyafrzronnu7sfaibu6pfz6y2beeb2q"
SSH_KEY_PATH="/Users/tejachowdary/.ssh/id_rsa.pub"
SHAPE="VM.Standard.A1.Flex"
OCPUS=4
MEMORY=24

# Possible Availability Domains in Phoenix
ADS=("kLpE:PHX-AD-1" "kLpE:PHX-AD-2" "kLpE:PHX-AD-3")

echo "🎯 Starting AirCatch Launch Sniper..."
echo "Press [CTRL+C] to stop."

while true; do
  for AD in "${ADS[@]}"; do
    echo "---------------------------------------------------"
    echo "$(date): Trying to hit target in $AD..."
    
    OUTPUT=$(oci compute instance launch \
      --availability-domain "$AD" \
      --compartment-id "$COMPARTMENT_ID" \
      --shape "$SHAPE" \
      --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY}" \
      --display-name "AirCatch-Relay" \
      --image-id "$IMAGE_ID" \
      --subnet-id "$SUBNET_ID" \
      --ssh-authorized-keys-file "$SSH_KEY_PATH" \
      --assign-public-ip true 2>&1)
    
    if [[ $OUTPUT == *"Out of host capacity"* ]]; then
      echo "❌ Missed: Out of capacity."
    elif [[ $OUTPUT == *"ServiceError"* ]]; then
      echo "⚠️  Error: $OUTPUT"
    else
      echo "✅ HIT! Instance launched successfully!"
      echo "$OUTPUT"
      echo "Check your Oracle Cloud Console!"
      exit 0
    fi
    
    sleep 5
  done
  
  echo "Sleeping for 60 seconds before reloading..."
  sleep 60
done
