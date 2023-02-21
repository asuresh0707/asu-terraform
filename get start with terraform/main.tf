### terraform block
terraform {
  required_version = "~>1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.27"
    }
  }
}


## provider block
provider "aws" {
  region = "us-east-1"
}



### aws ec2 instance
resource "aws_instance" "appserver" {
  ami                         = "ami-0dfcb1ef8550277af"
  instance_type               = "t2.micro"
  vpc_security_group_ids = [ aws_security_group.sshtraffic.id, aws_security_group.websg.id ]
  user_data                   = <<-EOF
     #!/bin/bash
     sudo yum update -y
     sudo yum install httpd -y
     sudo systemctl enable httpd && sudo systemctl start httpd
     echo "hello apache web server" >> /var/www/html/index.html
  EOF
  user_data_replace_on_change = true
  tags = {
    "environment" = "developement"
    "app"         = "web"
  }
}

### aws security group
resource "aws_security_group" "sshtraffic" {
  name        = "sg ssh"
  description = "secuirty group for allowing ssh traffic"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "ssh traffic rule"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "outbound traffic"
    from_port   = 1
    protocol    = "tcp"
    to_port     = 1
  }
}

resource "aws_security_group" "websg" {
  name        = "web security group"
  description = "web traffic for ec2 instance"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "web traffic for ec2 instance"
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  egress  {
    cidr_blocks = ["0.0.0.0/0"]
    description = "outbound traffic"
    from_port   = 1
    protocol    = "tcp"
    to_port     = 1
  }
}


### aws luanch configuration
resource "aws_launch_configuration" "alc" {
  image_id = "ami-0dfcb1ef8550277af"
  instance_type = "t2.micro"
  security_groups = [ aws_security_group.sshtraffic.id, aws_security_group.websg.id ]
  user_data                   = <<-EOF
     #!/bin/bash
     sudo yum update -y
     sudo yum install httpd -y
     sudo systemctl enable httpd && sudo systemctl start httpd
     echo "hello apache web server" >> /var/www/html/index.html
  EOF
  
  lifecycle {
    create_before_destroy = true
  }

}

### autoscaling group
resource "aws_autoscaling_group" "asg" {
  launch_configuration = aws_launch_configuration.alc.name
  vpc_zone_identifier = data.aws_subnets.dsub.ids
  target_group_arns = [aws_lb_target_group.lbtg.arn]
  health_check_type = "ELB"
  
  min_size = 1
  max_size = 2
}


### data sources to fetch vpc and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "dsub" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


### aws load balancer, listner, security-group for alb
resource "aws_lb" "alb" {
  name = "apploadbalncer"
  load_balancer_type = "application"
  subnets = data.aws_subnets.dsub.ids
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}


resource "aws_security_group" "lbsg" {
  name        = "load balancer security group"
  description = "web traffic for load balancer"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "web traffic for ALB"
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  egress  {
    cidr_blocks = ["0.0.0.0/0"]
    description = "outbound traffic"
    from_port   = 1
    protocol    = "tcp"
    to_port     = 1
  }
}

resource "aws_lb_target_group" "lbtg" {
  name = "lb-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id
  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }

}


resource "aws_lb_listener_rule" "lblis" {
  listener_arn = aws_lb_listener.listener.arn
  priority = 100
  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.lbtg.arn
  }
}


### output lb dns for single point of contact
output "alb_dns" {
  description = "the name of load balancer with single ip"
  value = aws_lb.alb.dns_name
}