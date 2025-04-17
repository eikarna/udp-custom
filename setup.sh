#!/bin/bash

set -euo pipefail

echo "Force linking all *.service files to /etc/systemd/system"
ln -sf *.service /etc/systemd/system
echo "Reloading systemctl daemon.."
systemctl daemon-reload
echo "Enabling service.."
systemctl enable --now $(find $(pwd) -type f -name "*.service" -printf "%f\n")
# reboot
