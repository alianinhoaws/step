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