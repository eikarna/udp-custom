#!/bin/bash

set -euo pipefail

currentDir=`pwd`

echo "Force linking all *.service files to /etc/systemd/system"
ln -sf $currentDir/*/**.service /etc/systemd/system
echo "Reloading systemctl daemon.."
systemctl daemon-reload
echo "Enabling service.."
systemctl enable --now $(find $currentDir -type f -name "*.service" -print0 | xargs -0 -n1 -P8 basename)
# reboot
