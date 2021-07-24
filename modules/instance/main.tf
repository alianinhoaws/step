
resource "aws_instance" "web" {
    ami = var.ami
    instance_type = lookup(var.ec2-size,var.env)
    vpc_security_group_ids = [var.security_group]
    subnet_id = var.subnet
    tags = {
      Name = "web"
    }
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