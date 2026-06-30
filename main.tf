provider "aws" {
  region = "eu-north-1"
}

#########################
# DATA
#########################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

#########################
# SECURITY GROUPS
#########################

resource "aws_security_group" "alb" {
  name = "terraform-alb"

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

resource "aws_security_group" "instance" {
  name = "terraform-instance"

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#########################
# LOAD BALANCER
#########################

resource "aws_lb" "example" {
  name               = "terraform-asg-example"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = 8080
  protocol = "HTTP"

  vpc_id = data.aws_vpc.default.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn

  port     = 80
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "asg" {

  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

#########################
# EC2
#########################

resource "aws_launch_configuration" "example" {

  image_id        = "ami-0aba19e56f3eaec05"
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
#!/bin/bash

mkdir -p /var/www/html

cat <<HTML > /var/www/html/index.html
<html>
<head>
<title>Terraform Demo</title>
</head>
<body style="font-family:Arial;text-align:center;margin-top:100px;">
<h1>🎉 Terraform Auto Scaling Group is working!</h1>
<h2>Load Balancer -> Auto Scaling -> EC2</h2>
<p>If you can see this page, everything is configured correctly.</p>
</body>
</html>
HTML

busybox httpd -f -p 8080 -h /var/www/html

EOF

  lifecycle {
    create_before_destroy = true
  }
}

#########################
# AUTO SCALING GROUP
#########################

resource "aws_autoscaling_group" "example" {

  launch_configuration = aws_launch_configuration.example.name

  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [
    aws_lb_target_group.asg.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size = 2
  max_size = 4

  tag {
    key                 = "Name"
    value               = "terraform-demo"
    propagate_at_launch = true
  }

  depends_on = [
    aws_lb_listener.http
  ]
}

#########################
# OUTPUT
#########################

output "alb_dns_name" {

  value = "http://${aws_lb.example.dns_name}"

}