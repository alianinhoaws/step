provider "aws" {
  region = "us-east-1"
}

variable "vcp_cidr" {
  default = "10.0.0.0/16"
}

variable "env" {
  default = "dev"
}

resource "aws_vpc" "main_vpc" {
  cidr_block = var.vcp_cidr
  tags = {
    Name = "vpc-${var.env}"  #"vpc-dev"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main_vpc.id
}

variable "public_subnet_ciders" {
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24"]
}

variable "private_subnet_ciders" {
  default = [
    "10.0.11.0/24",
    "10.0.22.0/24"]
}

data "aws_availability_zones" "available" {
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_ciders)
  cidr_block = element(var.public_subnet_ciders, count.index)
  map_public_ip_on_launch = true
  vpc_id = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_ciders)
  cidr_block = element(var.private_subnet_ciders, count.index)
  vpc_id = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
}


resource "aws_route_table" "public" {
  count = length(var.public_subnet_ciders)
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "${var.env}-public-${count.index + 1}"
  }
}

resource "aws_route_table" "private" {
  count = length(var.private_subnet_ciders)
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nats[count.index].id
  }
  tags = {
    Name = "${var.env}-private-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_ciders)
  route_table_id = aws_route_table.public[count.index].id
  subnet_id = element(aws_subnet.public[*].id, count.index)
}

resource "aws_route_table_association" "private" {
  count = length(var.public_subnet_ciders)
  route_table_id = aws_route_table.private[count.index].id
  subnet_id = element(aws_subnet.private[*].id, count.index)
}


resource "aws_eip" "ip_for_nat" { #100
  vpc = true
  count = length(var.private_subnet_ciders) # WE NEED TO HAVE 2 NAT Gateways  #100
  tags = {
    Name = "${var.env}-ip-for-nat-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nats" {
  allocation_id = aws_eip.ip_for_nat[count.index].id
  subnet_id = element(aws_subnet.public[*].id, count.index)
  count = length(var.private_subnet_ciders)
}

output "subnets" {
  value = aws_subnet.public[*]
}

resource "aws_security_group" "web_server" {
  vpc_id = aws_vpc.main_vpc.id
  name_prefix = "web"
  dynamic "ingress" {
    for_each = var.ports
    content {
      from_port = ingress.value
      protocol = "tcp"
      to_port = ingress.value
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "ports" {
  default = ["80","443"]
}

data "aws_ami" "amzon_linux" {
  owners = ["amazon"]
  most_recent = true
  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_configuration" "web" {
  image_id = data.aws_ami.amzon_linux.id
  instance_type = "t3.micro"
  security_groups = [aws_security_group.web_server.id]
  user_data = <<EOF
    #!/bin/bash
yum -y update
yum -y install httpd
PRIVATE_IP=`curl http://169.254.169.254/latest/meta-data/local-ipv4`
echo “Web Server has $PRIVATE_IP “ > /var/www/html/index.html
systemctl start httpd
systemctl enable httpd
    EOF
}

resource "aws_autoscaling_group" "web" {
  name_prefix = "Web"
  max_size = 4
  desired_capacity = 2
  min_size = 2
  vpc_zone_identifier = aws_subnet.public[*].id #[]
  health_check_type = "EC2"
  health_check_grace_period = 60
  default_cooldown = 30
  launch_configuration = aws_launch_configuration.web.name
  target_group_arns = [aws_lb_target_group.web.arn] #link
}


resource "aws_lb" "web" {
  name = "web"
  internal = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server.id]
  subnets            = aws_subnet.public.*.id #aws_subnet.public[*].id
  enable_deletion_protection = false
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_target_group" "web" {
  name     = "tf-example-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id
}

resource "aws_autoscaling_attachment" "web" { #link
  autoscaling_group_name = aws_autoscaling_group.web.id
  alb_target_group_arn = aws_lb_target_group.web.arn
}

resource "aws_autoscaling_policy" "cpu-up" {
  name                   = "cpu-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 30
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_cloudwatch_metric_alarm" "cpu-check-up" {
  alarm_name          = "cpu-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "50"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.cpu-up.arn]
}

resource "aws_autoscaling_policy" "cpu-down" {
  name                   = "cpu-up"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 30
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_cloudwatch_metric_alarm" "cpu-check-down" {
  alarm_name          = "cpu-alarm-down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "20"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.cpu-down.arn]
}

output "load_balancer_dns_name" {
  value = aws_lb.web.dns_name
}

