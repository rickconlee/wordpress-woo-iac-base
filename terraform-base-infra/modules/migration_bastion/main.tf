############################################
# migration_bastion/main.tf
#
# Scoped fix:
# - Ensure DNS resolution works reliably DURING cloud-init / early boot
# - Fix IMDSv2 usage (your logs show 401 from IMDS)
# - Install correct tooling on AL2023 (dig = bind-utils)
# - Wait for resolver + EFS DNS to resolve BEFORE attempting EFS mount
#
# No other “best practice” rewrites.
############################################

locals {
  # In every VPC, the Route 53 Resolver is always "VPC CIDR base + 2"
  # Example: 10.0.0.0/16 -> 10.0.0.2
  vpc_resolver_ip = cidrhost(var.vpc_cidr_block, 2)
}

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

  # Keep your locked-down egress pattern (as you already had it):
  egress = []

  revoke_rules_on_delete = true

  tags = merge(
    {
      Name = "${var.name}-migration-bastion"
    },
    var.tags
  )
}

############################################
# Egress rules
############################################

# Bastion -> RDS (MySQL) only
resource "aws_vpc_security_group_egress_rule" "bastion_to_db" {
  count = var.enable ? 1 : 0

  security_group_id            = aws_security_group.bastion[0].id
  referenced_security_group_id = var.db_security_group_id

  ip_protocol = "tcp"
  from_port   = 3306
  to_port     = 3306

  description = "Bastion egress to RDS (3306) only"
}

# Bastion -> EFS (NFS) only
resource "aws_vpc_security_group_egress_rule" "bastion_to_efs" {
  count = var.enable ? 1 : 0

  security_group_id            = aws_security_group.bastion[0].id
  referenced_security_group_id = var.efs_security_group_id

  ip_protocol = "tcp"
  from_port   = 2049
  to_port     = 2049

  description = "Bastion egress to EFS (2049) only"
}

# DNS to anywhere inside the VPC CIDR (UDP)
resource "aws_vpc_security_group_egress_rule" "bastion_dns_udp" {
  count = var.enable ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = var.vpc_cidr_block

  ip_protocol = "udp"
  from_port   = 53
  to_port     = 53

  description = "DNS (UDP) to VPC CIDR only"
}

# DNS to anywhere inside the VPC CIDR (TCP)
resource "aws_vpc_security_group_egress_rule" "bastion_dns_tcp" {
  count = var.enable ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = var.vpc_cidr_block

  ip_protocol = "tcp"
  from_port   = 53
  to_port     = 53

  description = "DNS (TCP) to VPC CIDR only"
}

# HTTPS outbound (package repos / TLS dependencies)
resource "aws_vpc_security_group_egress_rule" "bastion_https" {
  count = var.enable ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = "0.0.0.0/0"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  description = "HTTPS egress for OS repos / helpers"
}

############################################
# Instance
############################################

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

  # Keep IMDSv2 required (you explicitly set this already)
  metadata_options {
    http_tokens = "required"
  }

  user_data = <<EOF
#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== BEGIN bastion user_data ==="
date -Is

EFS_FS_ID="${var.efs_file_system_id}"
MOUNT_POINT="${var.efs_mount_point}"
FSTAB_OPTIONS="${var.efs_fstab_options}"

# IMDSv2 (your logs show 401 without this)
TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)"

REGION="$(curl -fsS -H "X-aws-ec2-metadata-token: $${TOKEN}" "http://169.254.169.254/latest/meta-data/placement/region" || true)"
if [ -z "$${REGION}" ]; then
  REGION="us-east-2"
fi

EFS_DNS="$${EFS_FS_ID}.efs.$${REGION}.amazonaws.com"

echo "EFS_FS_ID=$${EFS_FS_ID}"
echo "MOUNT_POINT=$${MOUNT_POINT}"
echo "FSTAB_OPTIONS=$${FSTAB_OPTIONS}"
echo "REGION=$${REGION}"
echo "EFS_DNS=$${EFS_DNS}"

mkdir -p "$${MOUNT_POINT}"

echo "--- resolv.conf ---"
cat /etc/resolv.conf || true

echo "--- route ---"
ip route || true

echo "--- install packages (latest available) ---"
if command -v dnf >/dev/null 2>&1; then
  dnf -y update
  dnf -y install amazon-efs-utils nfs-utils bind-utils
elif command -v yum >/dev/null 2>&1; then
  yum -y update
  yum -y install amazon-efs-utils nfs-utils bind-utils
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get -y install amazon-efs-utils nfs-common dnsutils
else
  echo "FATAL: No supported package manager found"
  exit 1
fi

echo "--- DNS sanity check (resolver + EFS) ---"
# VPC resolver IP should be var.vpc_cidr base + 2, but we just test via system config:
RESOLVER_IP="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf || true)"
echo "RESOLVER_IP=$${RESOLVER_IP}"

echo "dig @resolver . NS"
if [ -n "$${RESOLVER_IP}" ]; then
  dig @"$${RESOLVER_IP}" . NS +time=1 +tries=1 || true
fi

echo "dig @resolver EFS A"
if [ -n "$${RESOLVER_IP}" ]; then
  dig @"$${RESOLVER_IP}" "$${EFS_DNS}" A +short +time=1 +tries=1 || true
fi

echo "getent hosts EFS"
getent hosts "$${EFS_DNS}" || true

echo "--- write fstab (idempotent) ---"
FSTAB_LINE="$${EFS_FS_ID}:/ $${MOUNT_POINT} efs $${FSTAB_OPTIONS} 0 0"
if ! grep -Fq "$${FSTAB_LINE}" /etc/fstab; then
  echo "$${FSTAB_LINE}" >> /etc/fstab
fi

cat >/usr/local/sbin/mount-efs.sh <<EOM
#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/mount-efs.log | logger -t mount-efs -s 2>/dev/console) 2>&1

echo "=== BEGIN mount-efs.sh ==="
date -Is

EFS_FS_ID="${var.efs_file_system_id}"
MOUNT_POINT="${var.efs_mount_point}"
FSTAB_OPTIONS="${var.efs_fstab_options}"

# IMDSv2
TOKEN="\$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)"
REGION="\$(curl -fsS -H "X-aws-ec2-metadata-token: \$${TOKEN}" "http://169.254.169.254/latest/meta-data/placement/region" || true)"
if [ -z "\$${REGION}" ]; then
  REGION="us-east-2"
fi

EFS_DNS="\$${EFS_FS_ID}.efs.\$${REGION}.amazonaws.com"

mkdir -p "\$${MOUNT_POINT}"

echo "EFS_FS_ID=\$${EFS_FS_ID}"
echo "REGION=\$${REGION}"
echo "EFS_DNS=\$${EFS_DNS}"
echo "MOUNT_POINT=\$${MOUNT_POINT}"

echo "--- resolver config ---"
cat /etc/resolv.conf || true

echo "--- route ---"
ip route || true

RESOLVER_IP="\$(awk '/^nameserver/{print \$2; exit}' /etc/resolv.conf || true)"
echo "RESOLVER_IP=\$${RESOLVER_IP}"

echo "--- wait for DNS to be usable (resolver + EFS name) ---"
# This is the scoped fix: make DNS work DURING early boot, before EFS mount attempts.
for i in \$(seq 1 60); do
  if [ -n "\$${RESOLVER_IP}" ]; then
    dig @"\$${RESOLVER_IP}" . NS +time=1 +tries=1 >/dev/null 2>&1 || true
    if dig @"\$${RESOLVER_IP}" "\$${EFS_DNS}" A +short +time=1 +tries=1 | grep -E '^[0-9]+\.' >/dev/null 2>&1; then
      echo "DNS OK for \$${EFS_DNS}"
      break
    fi
  fi

  if getent hosts "\$${EFS_DNS}" >/dev/null 2>&1; then
    echo "DNS OK for \$${EFS_DNS} (getent)"
    break
  fi

  echo "DNS not ready yet (\$${i}/60)"
  sleep 1
done

echo "--- DNS check final ---"
if [ -n "\$${RESOLVER_IP}" ]; then
  dig @"\$${RESOLVER_IP}" "\$${EFS_DNS}" A +short +time=1 +tries=1 || true
fi
getent hosts "\$${EFS_DNS}" || true

if mountpoint -q "\$${MOUNT_POINT}"; then
  echo "Already mounted."
  exit 0
fi

attempt=1
max_attempts=60
sleep_seconds=2

while [ "\$${attempt}" -le "\$${max_attempts}" ]; do
  echo "Attempt \$${attempt}/\$${max_attempts}: mount -t efs -o \$${FSTAB_OPTIONS} \$${EFS_FS_ID}:/ \$${MOUNT_POINT}"
  mount -t efs -o "\$${FSTAB_OPTIONS}" "\$${EFS_FS_ID}:/" "\$${MOUNT_POINT}" || true

  if mountpoint -q "\$${MOUNT_POINT}"; then
    echo "Mounted OK."
    exit 0
  fi

  sleep "\$${sleep_seconds}"
  attempt=\$((attempt + 1))
done

echo "FATAL: EFS did not mount at \$${MOUNT_POINT}"
echo "--- journal tail ---"
journalctl -n 200 --no-pager || true
exit 1
EOM

chmod 0755 /usr/local/sbin/mount-efs.sh

cat >/etc/systemd/system/mount-efs.service <<'EOM'
[Unit]
Description=Mount EFS (migration bastion)
Wants=network-online.target
After=network-online.target systemd-resolved.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mount-efs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOM

systemctl daemon-reload
systemctl enable mount-efs.service
systemctl restart mount-efs.service

echo "--- mount status ---"
mount | grep -E "efs|$${MOUNT_POINT}" || true
df -h | grep -E "efs|$${MOUNT_POINT}" || true
ls -la "$${MOUNT_POINT}" || true

mkdir -p "$${MOUNT_POINT}/wp-content"

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

############################################
# Ingress allowances on EFS + RDS SGs
############################################

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
