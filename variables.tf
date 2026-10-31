variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name"
}

variable "my_ip" {
  type        = string
  description = "Your public IP in CIDR form, e.g. 203.0.113.5/32 (client C)"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
