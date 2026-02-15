resource "aws_security_group" "bastion" {
  count  = var.enable ? 1 : 0
  name   = "${var.name}-migration-bastion"
  vpc_id = var.vpc_id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  tags = merge(
    {
      Name = "${var.name}-migration-bastion"
    },
    var.tags
  )
}

resource "aws_instance" "bastion" {
  count         = var.enable ? 1 : 0
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  associate_public_ip_address = true
  key_name                    = var.key_name

  vpc_security_group_ids = [
    aws_security_group.bastion[0].id
  ]

  user_data = <<EOF
#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== BEGIN bastion user_data ==="
date -Is

EFS_FS_ID="${var.efs_file_system_id}"
MOUNT_POINT="${var.efs_mount_point}"
FSTAB_OPTIONS="${var.efs_fstab_options}"

REGION="$$(curl -fsS http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F'"' '{print $$4}' || true)"
if [ -z "$${REGION}" ]; then
  REGION="us-east-2"
fi

EFS_DNS="$${EFS_FS_ID}.efs.$${REGION}.amazonaws.com"

mkdir -p "$${MOUNT_POINT}"

install_pkgs() {
  echo "Installing mount tooling..."
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install amazon-efs-utils nfs-utils python3-botocore || dnf -y install amazon-efs-utils nfs-utils
  elif command -v yum >/dev/null 2>&1; then
    yum -y install amazon-efs-utils nfs-utils python3-botocore || yum -y install amazon-efs-utils nfs-utils
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get -y install amazon-efs-utils nfs-common python3-botocore
  else
    echo "FATAL: No supported package manager found"
    exit 1
  fi
}

wait_for_dns() {
  echo "Waiting for EFS DNS to resolve: $${EFS_DNS}"
  attempt=1
  max_attempts=60
  sleep_seconds=2

  while [ "$${attempt}" -le "$${max_attempts}" ]; do
    if getent hosts "$${EFS_DNS}" >/dev/null 2>&1; then
      echo "DNS OK: $${EFS_DNS}"
      return 0
    fi
    echo "DNS not ready ($${attempt}/$${max_attempts})..."
    sleep "$${sleep_seconds}"
    attempt=$((attempt + 1))
  done

  echo "WARNING: DNS still not resolving for $${EFS_DNS} after retries"
  return 1
}

cat >/usr/local/sbin/mount-efs.sh <<'EOS'
#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/mount-efs.log | logger -t mount-efs -s) 2>&1

echo "=== BEGIN mount-efs.sh ==="
date -Is

EFS_FS_ID="__EFS_FS_ID__"
MOUNT_POINT="__MOUNT_POINT__"
FSTAB_OPTIONS="__FSTAB_OPTIONS__"
REGION="__REGION__"
EFS_DNS="$${EFS_FS_ID}.efs.$${REGION}.amazonaws.com"

mkdir -p "$${MOUNT_POINT}"

echo "EFS_FS_ID=$${EFS_FS_ID}"
echo "REGION=$${REGION}"
echo "EFS_DNS=$${EFS_DNS}"
echo "MOUNT_POINT=$${MOUNT_POINT}"

echo "--- resolver config ---"
cat /etc/resolv.conf || true

echo "--- route ---"
ip route || true

echo "--- DNS check ---"
getent hosts "$${EFS_DNS}" || true

FSTAB_LINE="$${EFS_FS_ID}:/ $${MOUNT_POINT} efs $${FSTAB_OPTIONS} 0 0"
if ! grep -Fq "$${FSTAB_LINE}" /etc/fstab; then
  echo "$${FSTAB_LINE}" >> /etc/fstab
fi

if mountpoint -q "$${MOUNT_POINT}"; then
  echo "Already mounted."
  exit 0
fi

attempt=1
max_attempts=60
sleep_seconds=2

while [ "$${attempt}" -le "$${max_attempts}" ]; do
  echo "Attempt $${attempt}/$${max_attempts}: mount -t efs -o $${FSTAB_OPTIONS} $${EFS_FS_ID}:/ $${MOUNT_POINT}"
  if mount -t efs -o "$${FSTAB_OPTIONS}" "$${EFS_FS_ID}:/" "$${MOUNT_POINT}"; then
    if mountpoint -q "$${MOUNT_POINT}"; then
      echo "Mounted OK."
      exit 0
    fi
  fi

  echo "Mount attempt failed; sleeping..."
  sleep "$${sleep_seconds}"
  attempt=$((attempt + 1))
done

echo "FATAL: EFS did not mount at $${MOUNT_POINT}"
echo "--- journal tail ---"
journalctl -n 200 --no-pager || true
exit 1
EOS

sed -i "s|__EFS_FS_ID__|$${EFS_FS_ID}|g" /usr/local/sbin/mount-efs.sh
sed -i "s|__MOUNT_POINT__|$${MOUNT_POINT}|g" /usr/local/sbin/mount-efs.sh
sed -i "s|__FSTAB_OPTIONS__|$${FSTAB_OPTIONS}|g" /usr/local/sbin/mount-efs.sh
sed -i "s|__REGION__|$${REGION}|g" /usr/local/sbin/mount-efs.sh

chmod 0755 /usr/local/sbin/mount-efs.sh

cat >/etc/systemd/system/mount-efs.service <<'EOS'
[Unit]
Description=Mount EFS (migration bastion)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mount-efs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOS

install_pkgs
wait_for_dns || true

systemctl daemon-reload
systemctl enable mount-efs.service
systemctl restart mount-efs.service

mkdir -p "$${MOUNT_POINT}/wordpress"

echo "=== END bastion user_data ==="
date -Is
EOF

  tags = merge(
    {
      Name = "${var.name}-migration-bastion"
    },
    var.tags
  )
}

############################
# Bastion egress: ONLY to EFS and RDS (plus DNS + HTTPS for repos)
############################

resource "aws_security_group_rule" "bastion_egress_to_db" {
  count                    = var.enable ? 1 : 0
  type                     = "egress"
  security_group_id        = aws_security_group.bastion[0].id
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = var.db_security_group_id
  description              = "Bastion to RDS only"
}

resource "aws_security_group_rule" "bastion_egress_to_efs" {
  count                    = var.enable ? 1 : 0
  type                     = "egress"
  security_group_id        = aws_security_group.bastion[0].id
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = var.efs_security_group_id
  description              = "Bastion to EFS only"
}

resource "aws_security_group_rule" "bastion_egress_dns_udp" {
  count             = var.enable ? 1 : 0
  type              = "egress"
  security_group_id = aws_security_group.bastion[0].id
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Bastion DNS (UDP) to VPC resolver"
}

resource "aws_security_group_rule" "bastion_egress_dns_tcp" {
  count             = var.enable ? 1 : 0
  type              = "egress"
  security_group_id = aws_security_group.bastion[0].id
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Bastion DNS (TCP) to VPC resolver"
}

resource "aws_security_group_rule" "bastion_egress_https" {
  count             = var.enable ? 1 : 0
  type              = "egress"
  security_group_id = aws_security_group.bastion[0].id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS egress for OS repos / helper"
}

############################
# Allow EFS + RDS to accept from bastion
############################

resource "aws_security_group_rule" "efs_from_bastion" {
  count                    = var.enable ? 1 : 0
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = var.efs_security_group_id
  source_security_group_id = aws_security_group.bastion[0].id
  description              = "EFS from migration bastion only"
}

resource "aws_security_group_rule" "db_from_bastion" {
  count                    = var.enable ? 1 : 0
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = var.db_security_group_id
  source_security_group_id = aws_security_group.bastion[0].id
  description              = "RDS from migration bastion only"
}
