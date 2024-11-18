terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.41"
    }

    ansible = {
      version = "~> 1.3.0"
      source  = "ansible/ansible"
    }
  }

  backend "s3" {
    bucket = "tfpocbucket001"
    key    = "kubernetes/terraform.tfstate"
    region = "eu-north-1"
  }
}

provider "aws" {
  region = local.region
}

locals {
  region = "ap-south-2"

  ami           = "ami-0867df9d01e38f97d"
  instance_type = "t3.medium"
  workers_count = 2

  tags = {
    Name = "k8s-ec2-public"
    env  = "dev"
  }
}

#VPC
resource "aws_vpc" "k8s_vpc" {
  cidr_block = "172.16.0.0/16"
  tags       = local.tags
}

#INTERNET GATEWAY (IGW) 
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = local.tags
}

#SUBNET
resource "aws_subnet" "k8s_public_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "172.16.1.0/24"
  map_public_ip_on_launch = true
  tags                    = local.tags
}

# ROUTE TABLE
resource "aws_route_table" "k8s_route_table" {
  vpc_id = aws_vpc.k8s_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }
  tags = local.tags
}

# subnet attachment to ROUTE TABLE
resource "aws_route_table_association" "k8s_route_table_association" {
  depends_on = [
    aws_subnet.k8s_public_subnet
  ]
  subnet_id      = aws_subnet.k8s_public_subnet.id
  route_table_id = aws_route_table.k8s_route_table.id
}

# SECURITY GROUP
resource "aws_security_group" "k8s_sg" {
  vpc_id = aws_vpc.k8s_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ingress {
  #   from_port   = 80
  #   to_port     = 80
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # ingress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags

}

# RSA KEY PAIR
resource "tls_private_key" "foo" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "foo" {
  key_name   = "id_rsa"
  public_key = tls_private_key.foo.public_key_openssh
}

output "ssh_key" {
  value     = tls_private_key.foo.private_key_pem
  sensitive = true
}

# CONTROL PLANE NETWORK INTERFACE
resource "aws_network_interface" "network_interface_control_plane" {
  subnet_id       = aws_subnet.k8s_public_subnet.id
  security_groups = [aws_security_group.k8s_sg.id]
  tags            = merge(local.tags, { Name = "Control-Plane-ENI" })
}

# CONTROL PLANE INSTANCE
resource "aws_instance" "k8s_control_plane" {
  ami           = local.ami
  instance_type = local.instance_type
  key_name      = aws_key_pair.foo.key_name

  # Attach the network interface
  network_interface {
    network_interface_id = aws_network_interface.network_interface_control_plane.id
    device_index         = 0
  }

  tags = merge(local.tags, { Name = "Control-Plane" })
}

# WORKER NETWORK INTERFACES
resource "aws_network_interface" "network_interface_worker" {
  count           = local.workers_count
  subnet_id       = aws_subnet.k8s_public_subnet.id
  security_groups = [aws_security_group.k8s_sg.id]
  tags            = merge(local.tags, { Name = "Worker-ENI-${count.index + 1}" })
}

# WORKER INSTANCES
resource "aws_instance" "k8s_worker" {
  count         = local.workers_count
  ami           = local.ami
  instance_type = local.instance_type
  key_name      = aws_key_pair.foo.key_name

  # Attach each worker instance to its corresponding network interface
  network_interface {
    network_interface_id = aws_network_interface.network_interface_worker[count.index].id
    device_index         = 0
  }

  tags = merge(local.tags, { Name = "Worker-${count.index + 1}" })
}

output "control_plane_ip" {
  value = aws_instance.k8s_control_plane.public_ip
}

output "worker_ips" {
  value = [for instance in aws_instance.k8s_worker : instance.public_ip]
}

# ansible ansible-inventory -i inventory.yml --list (show the inventory)
resource "ansible_host" "manager" {
  name   = aws_instance.k8s_control_plane.public_ip
  groups = ["manager"]
  variables = {
    ansible_user                 = "ubuntu"
    ansible_ssh_private_key_file = "id_rsa.pem"
    ansible_connection           = "ssh"
    ansible_ssh_common_args      = "-o StrictHostKeyChecking=no"
    ansible_python_interpreter   = "/usr/bin/python3"
  }
}

resource "ansible_host" "worker" {
  count  = local.workers_count
  name   = aws_instance.k8s_worker[count.index].public_ip
  groups = ["worker"]
  variables = {
    ansible_user                 = "ubuntu"
    ansible_ssh_private_key_file = "id_rsa.pem"
    ansible_connection           = "ssh"
    ansible_ssh_common_args      = "-o StrictHostKeyChecking=no"
    ansible_python_interpreter   = "/usr/bin/python3"
  }
}
