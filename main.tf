provider "aws" {
  
  region = "eu-north-1"
}


resource "aws_instance" "example" {
  ami = "ami-023b6eace47afd3b4"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.example.ids]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p 80 &
              EOF
  user_data_replace_on_change = true
  tags = {
    Name="terraform-example"
  }
}



resource "aws_security_group" "example" {
  name = "terraform-example-instance"

  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 
}


variable "server_port" {
  description = "value"
  type = number
  default = 8080
}

output "public_ip" {
  value = aws_instance.example.public_ip
  description = "The public IP address of the web server"
}