terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Default VPC Information
data "aws_vpc" "primary" {
  default = true
}

data "aws_subnets" "vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
}

# Security Group for ALB
resource "aws_security_group" "web_lb_sg" {
  name        = "web-lb-sg-hm"
  description = "ALB Security Group"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for Web Servers
resource "aws_security_group" "app_server_sg" {
  name        = "app-server-sg-hm"
  description = "Web Server Security Group"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web_lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "linux2023" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Web Server 1
resource "aws_instance" "frontend_a" {
  ami                         = data.aws_ami.linux2023.id
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnets.vpc_subnets.ids[0]
  vpc_security_group_ids      = [aws_security_group.app_server_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
dnf install -y httpd
systemctl enable httpd
systemctl start httpd

cat > /var/www/html/index.html <<HTML
<h1>Application Node A</h1>
<p>Provisioned using Terraform</p>
HTML
EOF

  tags = {
    Name        = "hm-node-a"
    Environment = "Dev"
    Owner       = "Harsh"
  }
}

# Web Server 2
resource "aws_instance" "frontend_b" {
  ami                         = data.aws_ami.linux2023.id
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnets.vpc_subnets.ids[1]
  vpc_security_group_ids      = [aws_security_group.app_server_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
dnf install -y httpd
systemctl enable httpd
systemctl start httpd

cat > /var/www/html/index.html <<HTML
<h1>Application Node B</h1>
<p>Provisioned using Terraform</p>
HTML
EOF

  tags = {
    Name        = "hm-node-b"
    Environment = "Dev"
    Owner       = "Harsh"
  }
}

# Application Load Balancer
resource "aws_lb" "application_lb" {
  name               = "hm-app-loadbalancer"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.web_lb_sg.id
  ]

  subnets = [
    data.aws_subnets.vpc_subnets.ids[0],
    data.aws_subnets.vpc_subnets.ids[1]
  ]

  tags = {
    Project = "WebPlatform"
  }
}

# Target Group
resource "aws_lb_target_group" "web_targets" {
  name     = "hm-web-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.primary.id

  health_check {
    path                = "/"
    interval            = 20
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# Listener
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.application_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_targets.arn
  }
}

# Attach Instance A
resource "aws_lb_target_group_attachment" "node_a_attachment" {
  target_group_arn = aws_lb_target_group.web_targets.arn
  target_id        = aws_instance.frontend_a.id
  port             = 80
}

# Attach Instance B
resource "aws_lb_target_group_attachment" "node_b_attachment" {
  target_group_arn = aws_lb_target_group.web_targets.arn
  target_id        = aws_instance.frontend_b.id
  port             = 80
}

output "load_balancer_endpoint" {
  description = "Public DNS of the Application Load Balancer"
  value       = aws_lb.application_lb.dns_name
}