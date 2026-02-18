##################
# Networking
##################

# VPC
resource "aws_vpc" "demo" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Subnets split across 2 availability zones
resource "aws_subnet" "a" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "b" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true
}

# Internet Gateway and Route Table for the above subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.demo.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.b.id
  route_table_id = aws_route_table.public.id
}

##################
# Security Groups
##################

# Security group for all the web facing stuff
resource "aws_security_group" "web" {
  name   = "web"
  vpc_id = aws_vpc.demo.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.demo.cidr_block]
    description = "NLB health check port"
  }

  # Best-practice egress:
  # - NFS only to EFS SG
  # - MySQL only to DB SG
  # - DNS only to the VPC resolver (10.0.0.2)
  # - HTTPS allowed out for OS repos, etc.

  egress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.efs.id]
    description     = "NFS to EFS only"
  }

  egress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.db.id]
    description     = "MySQL to RDS only"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS egress for repos/helpers"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["10.0.0.2/32"]
    description = "DNS (UDP) to VPC resolver only"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.2/32"]
    description = "DNS (TCP) to VPC resolver only"
  }
}

resource "aws_security_group" "efs" {
  name   = "efs"
  vpc_id = aws_vpc.demo.id
}

resource "aws_security_group_rule" "efs_from_web" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = aws_security_group.web.id
}

resource "aws_security_group" "db" {
  name   = "db"
  vpc_id = aws_vpc.demo.id
}

resource "aws_security_group_rule" "db_from_web" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.web.id
}

##################
# EFS
##################

resource "aws_efs_file_system" "wp" {
  throughput_mode = "bursting"
}

resource "aws_efs_mount_target" "a" {
  file_system_id  = aws_efs_file_system.wp.id
  subnet_id       = aws_subnet.a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "b" {
  file_system_id  = aws_efs_file_system.wp.id
  subnet_id       = aws_subnet.b.id
  security_groups = [aws_security_group.efs.id]
}

##################
# RDS
##################

resource "aws_db_subnet_group" "db" {
  subnet_ids = [
    aws_subnet.a.id,
    aws_subnet.b.id
  ]
}

resource "aws_db_instance" "mysql" {
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.mysql_database_name
  username               = var.mysql_user_name
  password               = var.mysql_user_password
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
}

#########################
# Network Load Balancer
#########################

resource "aws_lb" "nlb" {
  name               = "lolzify-nlb"
  load_balancer_type = "network"
  subnets            = [
    aws_subnet.a.id,
    aws_subnet.b.id
  ]
}

resource "aws_lb_target_group" "tg" {
  port     = 443
  protocol = "TCP"
  vpc_id   = aws_vpc.demo.id

  health_check {
    port     = "8443"
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

######################
# WordPress Secrets
######################

resource "random_password" "auth_key" {
  length  = 64
  special = true
}

resource "random_password" "secure_auth_key" {
  length  = 64
  special = true
}

resource "random_password" "logged_in_key" {
  length  = 64
  special = true
}

resource "random_password" "nonce_key" {
  length  = 64
  special = true
}

resource "random_password" "auth_salt" {
  length  = 64
  special = true
}

resource "random_password" "secure_auth_salt" {
  length  = 64
  special = true
}

resource "random_password" "logged_in_salt" {
  length  = 64
  special = true
}

resource "random_password" "nonce_salt" {
  length  = 64
  special = true
}

##################
# EC2 / ASG
##################

resource "aws_launch_template" "wp" {
  image_id      = var.ami_image_id
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }

  user_data = base64encode(<<EOF
#cloud-config
output:
  all: "| tee -a /var/log/cloud-init-output.log > /dev/console"

write_files:
  - path: /usr/local/bin/mount-efs-wp-content.sh
    owner: root:root
    permissions: "0755"
    content: |
      #!/bin/bash
      set -euo pipefail

      echo "=== BEGIN mount-efs-wp-content.sh ==="
      date -Is

      EFS_FS_ID="${aws_efs_file_system.wp.id}"
      AWS_REGION="us-east-2"

      EFS_MOUNT="/mnt/efs"
      LOCAL_WP_ROOT="/var/www/html"
      LOCAL_WP_CONTENT="$${LOCAL_WP_ROOT}/wp-content"
      EFS_WP_CONTENT="$${EFS_MOUNT}/wp-content"

      EFS_FQDN="$${EFS_FS_ID}.efs.$${AWS_REGION}.amazonaws.com"

      echo "EFS_FS_ID=$${EFS_FS_ID}"
      echo "AWS_REGION=$${AWS_REGION}"
      echo "EFS_FQDN=$${EFS_FQDN}"
      echo "EFS_MOUNT=$${EFS_MOUNT}"
      echo "EFS_WP_CONTENT=$${EFS_WP_CONTENT}"
      echo "LOCAL_WP_CONTENT=$${LOCAL_WP_CONTENT}"

      dnf -y install amazon-efs-utils nfs-utils python3-botocore

      mkdir -p "$${EFS_MOUNT}"
      mkdir -p "$${LOCAL_WP_CONTENT}"

      echo "--- resolv.conf ---"
      cat /etc/resolv.conf || true

      echo "--- wait for DNS to be ready (up to 120s) ---"
      dns_attempt=1
      dns_max_attempts=60
      while [ "$${dns_attempt}" -le "$${dns_max_attempts}" ]; do
        if getent hosts "$${EFS_FQDN}" >/dev/null 2>&1; then
          echo "DNS OK for $${EFS_FQDN}"
          break
        fi
        echo "DNS not ready yet ($${dns_attempt}/$${dns_max_attempts})"
        sleep 2
        dns_attempt=$((dns_attempt + 1))
      done

      echo "--- trying DNS for EFS (final) ---"
      getent hosts "$${EFS_FQDN}" || true

      echo "--- mount EFS explicitly (retry) ---"
      attempt=1
      max_attempts=60
      while [ "$${attempt}" -le "$${max_attempts}" ]; do
        if mountpoint -q "$${EFS_MOUNT}"; then
          echo "EFS already mounted at $${EFS_MOUNT}"
          break
        fi

        mount -t efs -o tls,_netdev "$${EFS_FS_ID}":/ "$${EFS_MOUNT}" || true

        if mountpoint -q "$${EFS_MOUNT}"; then
          echo "EFS mounted at $${EFS_MOUNT}"
          break
        fi

        echo "Attempt $${attempt}/$${max_attempts}: EFS not mounted yet"
        sleep 2
        attempt=$((attempt + 1))
      done

      echo "--- mount | grep efs ---"
      mount | grep -E "efs|$${EFS_MOUNT}" || true
      echo "--- df -h | grep efs ---"
      df -h | grep -E "efs|$${EFS_MOUNT}" || true

      if ! mountpoint -q "$${EFS_MOUNT}"; then
        echo "FATAL: EFS did not mount at $${EFS_MOUNT}"
        exit 1
      fi

      echo "Ensuring EFS wp-content directory exists BEFORE bind mount (mkdir -p)..."
      mkdir -p "$${EFS_WP_CONTENT}"

      echo "--- bind mount wp-content explicitly (retry) ---"
      attempt=1
      max_attempts=60
      while [ "$${attempt}" -le "$${max_attempts}" ]; do
        if mountpoint -q "$${LOCAL_WP_CONTENT}"; then
          echo "wp-content already mounted at $${LOCAL_WP_CONTENT}"
          break
        fi

        mount --bind "$${EFS_WP_CONTENT}" "$${LOCAL_WP_CONTENT}" || true

        if mountpoint -q "$${LOCAL_WP_CONTENT}"; then
          echo "Bind mount OK: $${EFS_WP_CONTENT} -> $${LOCAL_WP_CONTENT}"
          break
        fi

        echo "Attempt $${attempt}/$${max_attempts}: bind mount not active yet"
        sleep 2
        attempt=$((attempt + 1))
      done

      if ! mountpoint -q "$${LOCAL_WP_CONTENT}"; then
        echo "FATAL: bind mount did not activate for $${LOCAL_WP_CONTENT}"
        echo "--- mount output ---"
        mount | grep -E "$${EFS_MOUNT}|$${LOCAL_WP_CONTENT}" || true
        exit 1
      fi

      echo "--- mount | grep wp-content ---"
      mount | grep -E "$${LOCAL_WP_CONTENT}|$${EFS_WP_CONTENT}" || true

      echo "--- NOTE: wp-content may be empty until restore. This is OK. ---"
      echo "--- ls -la $${LOCAL_WP_CONTENT} ---"
      ls -la "$${LOCAL_WP_CONTENT}" || true

      echo "--- ownership sanity (optional but recommended) ---"
      chown -R nginx:nginx "$${LOCAL_WP_CONTENT}" || true

      echo "Ensuring wp-config.php exists (idempotent)..."
      WP_CONFIG="$${LOCAL_WP_ROOT}/wp-config.php"
      if [ ! -f "$${WP_CONFIG}" ]; then
        cat > "$${WP_CONFIG}" <<'EOC'
      <?php
      define('DB_NAME', '${aws_db_instance.mysql.db_name}');
      define('DB_USER', '${aws_db_instance.mysql.username}');
      define('DB_PASSWORD', '${aws_db_instance.mysql.password}');
      define('DB_HOST', '${aws_db_instance.mysql.address}');
      define('DB_CHARSET', 'utf8mb4');
      define('DB_COLLATE', '');

      define('AUTH_KEY',         '${random_password.auth_key.result}');
      define('SECURE_AUTH_KEY',  '${random_password.secure_auth_key.result}');
      define('LOGGED_IN_KEY',    '${random_password.logged_in_key.result}');
      define('NONCE_KEY',        '${random_password.nonce_key.result}');
      define('AUTH_SALT',        '${random_password.auth_salt.result}');
      define('SECURE_AUTH_SALT', '${random_password.secure_auth_salt.result}');
      define('LOGGED_IN_SALT',   '${random_password.logged_in_salt.result}');
      define('NONCE_SALT',       '${random_password.nonce_salt.result}');

      $table_prefix = 'wp_';
      define('WP_DEBUG', false);
      define('FS_METHOD', 'direct');

      if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
        $_SERVER['HTTPS'] = 'on';
      }
      if (isset($_SERVER['HTTP_CF_VISITOR']) && strpos($_SERVER['HTTP_CF_VISITOR'], 'https') !== false) {
        $_SERVER['HTTPS'] = 'on';
      }
      define('FORCE_SSL_ADMIN', true);

      if (!defined('ABSPATH')) {
        define('ABSPATH', __DIR__ . '/');
      }

      require_once ABSPATH . 'wp-settings.php';
      EOC
        chown root:root "$${WP_CONFIG}" || true
        chmod 0644 "$${WP_CONFIG}" || true
      fi

      echo "=== SUCCESS mount-efs-wp-content.sh ==="
      date -Is

runcmd:
  - [ bash, -lc, "/usr/local/bin/mount-efs-wp-content.sh" ]
EOF
  )
  depends_on = [aws_efs_file_system.wp, aws_efs_mount_target.a, aws_efs_mount_target.b]
}

resource "aws_autoscaling_group" "wp" {
  desired_capacity = 2
  min_size         = 2
  max_size         = 2

  vpc_zone_identifier = [
    aws_subnet.a.id,
    aws_subnet.b.id
  ]

  launch_template {
    id      = aws_launch_template.wp.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    triggers = ["launch_template"]

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
  }
}

resource "aws_autoscaling_attachment" "asg" {
  autoscaling_group_name = aws_autoscaling_group.wp.name
  lb_target_group_arn    = aws_lb_target_group.tg.arn
  depends_on             = [aws_efs_file_system.wp, aws_efs_mount_target.a, aws_efs_mount_target.b]
}

##########################
# Cloudflare DNS
##########################

resource "cloudflare_record" "wp" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME"
  value   = aws_lb.nlb.dns_name
  ttl     = 1
  proxied = true
}

###########################################
# Migration Module (Disable when complete)
###########################################

module "migration_bastion" {
  source = "./modules/migration_bastion"

  name           = "lolzify"
  vpc_id         = aws_vpc.demo.id
  vpc_cidr_block = aws_vpc.demo.cidr_block

  subnet_id = aws_subnet.a.id

  ami_id        = var.ami_image_id
  instance_type = "t2.micro"

  key_name   = var.ssh_key_name
  my_ip_cidr = var.admin_ip

  efs_file_system_id = aws_efs_file_system.wp.id
  efs_mount_point    = "/mnt/efs"
  efs_fstab_options  = "tls,_netdev"

  db_security_group_id  = aws_security_group.db.id
  efs_security_group_id = aws_security_group.efs.id

  tags = {
    Project = "lolzify"
    Purpose = "migration"
  }

  depends_on = [aws_db_instance.mysql, aws_efs_file_system.wp]

  enable = true
}
