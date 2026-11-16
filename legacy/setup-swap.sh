#!/bin/sh
# Setup swap file for low-RAM VPS (1GB RAM)
# Run this BEFORE building Docker images

SWAPFILE="${SWAPFILE:-/swapfile}"
SIZE_MB="${SIZE_MB:-2048}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Must run as root (sudo sh setup-swap.sh)"
  exit 1
fi

if swapon --show | grep -q .; then
  echo "Swap already active:"
  swapon --show
  exit 0
fi

echo "Creating ${SIZE_MB}MB swap file at ${SWAPFILE}..."
fallocate -l "${SIZE_MB}M" "$SWAPFILE"
chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE"
swapon "$SWAPFILE"

echo "Making swap permanent (adds to /etc/fstab)..."
if ! grep -q "$SWAPFILE" /etc/fstab; then
  echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

echo "Done. Swap active:"
free -h
swapon --show

echo ""
echo "To disable swap later: sudo swapoff $SWAPFILE && rm $SWAPFILE"
