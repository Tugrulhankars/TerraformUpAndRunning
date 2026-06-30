terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.8"
}

provider "aws" {
  region = "eu-north-1"
}

########################################
# DATA
########################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {

  most_recent = true

  owners = ["099720109477"]

  filter {
    name = "name"

    values = [
      "ubuntu/images/hvm-ssd-gp3/ubuntu-24.04-amd64-server-*"
    ]
  }
}

########################################
# SECURITY GROUP ALB
########################################

resource "aws_security_group" "alb" {

  name = "terraform-alb"

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {

    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}

########################################
# SECURITY GROUP EC2
########################################

resource "aws_security_group" "instance" {

  name = "terraform-instance"

  ingress {

    from_port = 8080
    to_port   = 8080
    protocol  = "tcp"

    security_groups = [
      aws_security_group.alb.id
    ]
  }

  egress {

    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}

########################################
# LOAD BALANCER
########################################

resource "aws_lb" "example" {

  name = "terraform-demo"

  load_balancer_type = "application"

  subnets = data.aws_subnets.default.ids

  security_groups = [
    aws_security_group.alb.id
  ]
}

########################################
# TARGET GROUP
########################################

resource "aws_lb_target_group" "example" {

  name = "terraform-demo"

  port = 8080

  protocol = "HTTP"

  vpc_id = data.aws_vpc.default.id

  health_check {

    path = "/"

    matcher = "200"

    interval = 15

    timeout = 5

    healthy_threshold = 2

    unhealthy_threshold = 2
  }
}

########################################
# LISTENER
########################################

resource "aws_lb_listener" "http" {

  load_balancer_arn = aws_lb.example.arn

  port = 80

  protocol = "HTTP"

  default_action {

    type = "forward"

    target_group_arn = aws_lb_target_group.example.arn
  }
}

########################################
# LAUNCH TEMPLATE
########################################

resource "aws_launch_template" "example" {

  name_prefix = "terraform-demo-"

  image_id = data.aws_ami.ubuntu.id

  instance_type = "t3.micro"

  vpc_security_group_ids = [
    aws_security_group.instance.id
  ]

  user_data = base64encode(<<EOF
#!/bin/bash

apt-get update

apt-get install nginx -y

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>

<head>

<title>Terraform</title>

</head>

<body style="font-family:Arial;text-align:center;margin-top:100px;">

<h1>🎉 Terraform Success!</h1>

<h2>Application Load Balancer</h2>

<h2>↓</h2>

<h2>Auto Scaling Group</h2>

<h2>↓</h2>

<h2>Launch Template</h2>

<h2>↓</h2>

<h2>EC2 Instance</h2>

<p>If you can read this page everything is working correctly.</p>

</body>

</html>
HTML

systemctl enable nginx

systemctl restart nginx

apt-get install socat -y

socat TCP-LISTEN:8080,fork TCP:localhost:80 &

EOF
)

  tag_specifications {

    resource_type = "instance"

    tags = {

      Name = "Terraform-Demo"

    }
  }
}

########################################
# AUTO SCALING GROUP
########################################

resource "aws_autoscaling_group" "example" {

  min_size = 2

  max_size = 4

  desired_capacity = 2

  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [

    aws_lb_target_group.example.arn

  ]

  health_check_type = "ELB"

  health_check_grace_period = 300

  launch_template {

    id = aws_launch_template.example.id

    version = "$Latest"
  }

  tag {

    key = "Name"

    value = "Terraform-ASG"

    propagate_at_launch = true
  }
}

########################################
# OUTPUT
########################################

output "alb_dns_name" {

  value = "http://${aws_lb.example.dns_name}"
}