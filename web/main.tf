provider "aws" {
  region     = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "terraform-tf-state-alia2"
    region = "us-east-1"
    key    = "application/dev/terraform.tfstate"
  }
}

data "aws_ami" "amazon_linux" {
  owners = ["amazon"]
  most_recent = true
  filter {
      name = "name"
      values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

module "network" {
  source = "..\/moduless\/network"
  private_subnet_ciders = [
    "10.0.11.0/24"]
  public_subnet_ciders = var.public_subnet
  env = var.env
  vcp_cidr = "10.0.0.0/16"
}

module "instance" {
  source = "..\/moduless\/instance"
  ami = data.aws_ami.amazon_linux.id
  env = var.env
  security_group = module.network.sg_id
  subnet = module.network.subnets[0]
}


