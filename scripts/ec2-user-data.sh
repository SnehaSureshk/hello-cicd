#!/bin/bash
# Paste this into "Advanced details -> User data" when launching the EC2 instance.
# It installs Docker on Amazon Linux 2023 and lets ec2-user run docker without sudo.
dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user
