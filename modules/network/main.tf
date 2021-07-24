
resource "aws_vpc" "main_vpc" {
  cidr_block = var.vcp_cidr
  tags = {
    Name = "vpc-${var.env}" #"vpc-dev"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main_vpc.id
}


data "aws_availability_zones" "available" {
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_ciders)
  cidr_block              = element(var.public_subnet_ciders, count.index)
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main_vpc.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_ciders)
  cidr_block        = element(var.private_subnet_ciders, count.index)
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
}


resource "aws_route_table" "public" {
  count  = length(var.public_subnet_ciders)
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "${var.env}-public-${count.index + 1}"
  }
}


resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_ciders)
  route_table_id = aws_route_table.public[count.index].id
  subnet_id      = element(aws_subnet.public[*].id, count.index)
}

resource "aws_security_group" "web" {
    name_prefix = "web"
    vpc_id = aws_vpc.main_vpc.id
    dynamic "ingress" {
      for_each = ["80","443","22"]
      content {
        from_port = ingress.value #80 #443 #22
        to_port = ingress.value #80  #433 #22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
      }
    }
    egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
}