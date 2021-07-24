variable "env" {
  default = "dev"
}

variable "ec2-size" {
  default = {
    "prod"  = "t3.medium"
    "stage" = "t3.micro"
    "dev"   = "t2.micro"
    "test"  = "t2.micro"
  }
}

variable "ami" {
}

variable "security_group" {
}

variable "subnet" {
}