##################
# Networking
##################

resource "aws_vpc" "demo" {
  cidr_block = "10.0.0.0/16"
}

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

# Web (EC2)
resource "aws_security_group" "web" {
  name   = "web"
  vpc_id = aws_vpc.demo.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

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
}

# EFS
resource "aws_security_group" "efs" {
  name   = "efs"
  vpc_id = aws_vpc.demo.id
}

resource "aws_security_group_rule" "efs_from_web" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id         = aws_security_group.efs.id
  source_security_group_id  = aws_security_group.web.id
}

# RDS
resource "aws_security_group" "db" {
  name   = "db"
  vpc_id = aws_vpc.demo.id
}

resource "aws_security_group_rule" "db_from_web" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id         = aws_security_group.db.id
  source_security_group_id  = aws_security_group.web.id
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
  db_name                = "wordpress"
  username               = "wpadmin"
  password               = "changeme123!"
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
}

##################
# Network Load Balancer
##################

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

##################
# EC2 / ASG
##################

resource "aws_launch_template" "wp" {
  image_id      = "ami-05bf1d46393e681cc"
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }
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
