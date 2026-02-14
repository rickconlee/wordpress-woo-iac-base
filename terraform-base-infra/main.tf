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
  vpc_id            = aws_vpc.demo.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-2b"
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

# TODO: Fix all these egresses so they stay in the VPC (NFS, MYSQL, HTTPS, DNS)
  egress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

# The following items randomly generate those secrets and hashes that go in the wp-config.php file. 

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

      EFS_MOUNT="/mnt/efs"
      LOCAL_WP_ROOT="/var/www/html"
      LOCAL_WP_CONTENT="$${LOCAL_WP_ROOT}/wp-content"
      EFS_WP_CONTENT="$${EFS_MOUNT}/wp-content"

      echo "EFS_FS_ID=$${EFS_FS_ID}"
      echo "EFS_MOUNT=$${EFS_MOUNT}"
      echo "EFS_WP_CONTENT=$${EFS_WP_CONTENT}"
      echo "LOCAL_WP_CONTENT=$${LOCAL_WP_CONTENT}"

      dnf -y install amazon-efs-utils nfs-utils python3-botocore

      mkdir -p "$${EFS_MOUNT}"
      mkdir -p "$${LOCAL_WP_CONTENT}"

      EFS_FSTAB_LINE="$${EFS_FS_ID}:/ $${EFS_MOUNT} efs tls,_netdev,x-systemd.automount,nofail 0 0"
      if ! grep -Fq "$${EFS_FSTAB_LINE}" /etc/fstab; then
        echo "$${EFS_FSTAB_LINE}" >> /etc/fstab
      fi

      BIND_FSTAB_LINE="$${EFS_WP_CONTENT} $${LOCAL_WP_CONTENT} none bind,_netdev,x-systemd.automount,nofail 0 0"
      if ! grep -Fq "$${BIND_FSTAB_LINE}" /etc/fstab; then
        echo "$${BIND_FSTAB_LINE}" >> /etc/fstab
      fi

      echo "--- resolv.conf ---"
      cat /etc/resolv.conf || true

      echo "--- trying DNS for EFS ---"
      getent hosts "$${EFS_FS_ID}.efs.us-east-2.amazonaws.com" || true

      echo "Mounting (mount -a) with retry..."
      attempt=1
      max_attempts=60
      sleep_seconds=2

      while [ "$${attempt}" -le "$${max_attempts}" ]; do
        mount -a || true

        if mountpoint -q "$${EFS_MOUNT}"; then
          echo "EFS mounted at $${EFS_MOUNT}"
          break
        fi

        echo "Attempt $${attempt}/$${max_attempts}: EFS not mounted yet"
        sleep "$${sleep_seconds}"
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

      echo "Validating EFS wp-content structure..."
      if [ ! -d "$${EFS_WP_CONTENT}" ]; then
        echo "FATAL: Missing $${EFS_WP_CONTENT}"
        echo "--- ls -la $${EFS_MOUNT} ---"
        ls -la "$${EFS_MOUNT}" || true
        exit 1
      fi

      echo "Trigger bind automount by touching wp-content..."
      ls -la "$${LOCAL_WP_CONTENT}" || true

      echo "--- mount | grep wp-content ---"
      mount | grep -E "$${LOCAL_WP_CONTENT}|$${EFS_WP_CONTENT}" || true

      if [ ! -d "$${LOCAL_WP_CONTENT}/themes" ] || [ ! -d "$${LOCAL_WP_CONTENT}/plugins" ] || [ ! -d "$${LOCAL_WP_CONTENT}/uploads" ]; then
        echo "FATAL: wp-content does not look mounted (themes/plugins/uploads missing)"
        echo "--- ls -la $${LOCAL_WP_CONTENT} ---"
        ls -la "$${LOCAL_WP_CONTENT}" || true
        exit 1
      fi

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

  enable = true
}
