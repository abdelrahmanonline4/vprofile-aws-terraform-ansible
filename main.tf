# Four EC2 instances, one ALB and one NAT Gateway. No variables/modules/loops.
# Region-specific Ubuntu 22.04 AMI verified on 2026-11-02.
terraform {
  required_version = ">= 1.7, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "vprofile-lab", Environment = "lab", ManagedBy = "Terraform" }
  }
}

# NETWORK
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "vprofile-vpc" }
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "vprofile-public-a" }
}
resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "vprofile-public-b" }
}
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "vprofile-private" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "vprofile-nat-ip" }
}
resource "aws_nat_gateway" "main" {
  subnet_id     = aws_subnet.public_a.id
  allocation_id = aws_eip.nat.id
  depends_on    = [aws_internet_gateway.main]
  tags          = { Name = "vprofile-nat" }
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# SECURITY GROUPS: replace the two admin /32 entries if your public IP changes.
resource "aws_security_group" "alb" {
  name   = "vprofile-alb"
  vpc_id = aws_vpc.main.id
  ingress {
    description = "Browser from your public IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.10/32"] # ADMIN_IP
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "app" {
  name   = "vprofile-app"
  vpc_id = aws_vpc.main.id
  ingress {
    description = "SSH from your public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.10/32"] # ADMIN_IP
  }
  ingress {
    description     = "Tomcat from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name   = "vprofile-db"
  vpc_id = aws_vpc.main.id
  ingress {
    description     = "Ansible SSH from app01"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  ingress {
    description     = "Application service access from app01"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mc" {
  name   = "vprofile-mc"
  vpc_id = aws_vpc.main.id
  ingress {
    description     = "Ansible SSH from app01"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  ingress {
    description     = "Application service access from app01"
    from_port       = 11211
    to_port         = 11211
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rmq" {
  name   = "vprofile-rmq"
  vpc_id = aws_vpc.main.id
  ingress {
    description     = "Ansible SSH from app01"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  ingress {
    description     = "Application service access from app01"
    from_port       = 5672
    to_port         = 5672
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 key pairs store public keys only. SSH provisioners below read local private keys.
resource "aws_key_pair" "admin" {
  key_name   = "vprofile-admin"
  public_key = file("${path.module}/keys/admin.pub")
}
resource "aws_key_pair" "managed" {
  key_name   = "vprofile-managed"
  public_key = file("${path.module}/keys/managed.pub")
}

resource "aws_instance" "app01" {
  ami                         = "ami-033ea4ff4a9c726dc"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  private_ip                  = "10.0.1.10"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.admin.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  credit_specification {
    cpu_credits = "standard"
  }
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags       = { Name = "app01" }
  depends_on = [aws_route_table_association.public_a]
  # Install Ansible on app01 itself. No separate controller EC2.
  user_data                   = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y python3-venv
    python3 -m venv /opt/ansible
    /opt/ansible/bin/pip install 'ansible-core>=2.17,<2.18'
    ln -sf /opt/ansible/bin/ansible /usr/local/bin/ansible
    ln -sf /opt/ansible/bin/ansible-playbook /usr/local/bin/ansible-playbook
    sudo -u ubuntu /opt/ansible/bin/ansible-galaxy collection install community.mysql:3.16.1 community.rabbitmq:1.7.0
  EOF
  user_data_replace_on_change = true
}

resource "aws_instance" "db01" {
  ami                         = "ami-033ea4ff4a9c726dc"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private.id
  private_ip                  = "10.0.2.40"
  associate_public_ip_address = false
  key_name                    = aws_key_pair.managed.key_name
  vpc_security_group_ids      = [aws_security_group.db.id]
  credit_specification {
    cpu_credits = "standard"
  }
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags       = { Name = "db01" }
  depends_on = [aws_route_table_association.private]
}

resource "aws_instance" "mc01" {
  ami                         = "ami-033ea4ff4a9c726dc"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private.id
  private_ip                  = "10.0.2.20"
  associate_public_ip_address = false
  key_name                    = aws_key_pair.managed.key_name
  vpc_security_group_ids      = [aws_security_group.mc.id]
  credit_specification {
    cpu_credits = "standard"
  }
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags       = { Name = "mc01" }
  depends_on = [aws_route_table_association.private]
}

resource "aws_instance" "rmq01" {
  ami                         = "ami-033ea4ff4a9c726dc"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private.id
  private_ip                  = "10.0.2.30"
  associate_public_ip_address = false
  key_name                    = aws_key_pair.managed.key_name
  vpc_security_group_ids      = [aws_security_group.rmq.id]
  credit_specification {
    cpu_credits = "standard"
  }
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags       = { Name = "rmq01" }
  depends_on = [aws_route_table_association.private]
}

# APPLICATION LOAD BALANCER replaces Nginx.
resource "aws_lb" "main" {
  name                       = "vprofile-alb"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
}
resource "aws_lb_target_group" "tomcat" {
  name     = "vprofile-tomcat"
  vpc_id   = aws_vpc.main.id
  port     = 8080
  protocol = "HTTP"
  health_check {
    path                = "/login"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.tomcat.arn
  target_id        = aws_instance.app01.id
  port             = 8080
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tomcat.arn
  }
}

# RUN ANSIBLE AUTOMATICALLY FROM app01 AFTER ALL FOUR SERVERS EXIST.
# terraform_data is a built-in Terraform resource, NOT another EC2 or paid AWS service.
resource "terraform_data" "configure" {
  depends_on = [
    aws_instance.app01,
    aws_instance.db01,
    aws_instance.mc01,
    aws_instance.rmq01,
    aws_lb_listener.http,
    aws_lb_target_group_attachment.app
  ]

  # Re-run configuration after editing these files or replacing any server.
  # Ordinary applies with no changes do not rebuild the application.
  triggers_replace = [
    aws_instance.app01.id,
    aws_instance.db01.id,
    aws_instance.mc01.id,
    aws_instance.rmq01.id,
    filesha256("${path.module}/playbook.yml"),
    filesha256("${path.module}/inventory.ini"),
    filesha256("${path.module}/ansible.cfg")
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.app01.public_ip
    user        = "ubuntu"
    private_key = sensitive(file("${path.module}/keys/admin"))
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "timeout 900 cloud-init status --wait",
      "/opt/ansible/bin/ansible-playbook --version",
      "mkdir -p /home/ubuntu/vprofile /home/ubuntu/.ssh",
      "chmod 700 /home/ubuntu/vprofile /home/ubuntu/.ssh"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/playbook.yml"
    destination = "/home/ubuntu/vprofile/playbook.yml"
  }
  provisioner "file" {
    source      = "${path.module}/inventory.ini"
    destination = "/home/ubuntu/vprofile/inventory.ini"
  }
  provisioner "file" {
    source      = "${path.module}/ansible.cfg"
    destination = "/home/ubuntu/vprofile/ansible.cfg"
  }
  provisioner "file" {
    source      = "${path.module}/keys/managed"
    destination = "/home/ubuntu/.ssh/vprofile-managed"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "chmod 600 /home/ubuntu/.ssh/vprofile-managed",
      "cd /home/ubuntu/vprofile",
      "/opt/ansible/bin/ansible-playbook playbook.yml --syntax-check",
      "/opt/ansible/bin/ansible-playbook playbook.yml"
    ]
  }
}

output "app_public_ip" {
  value = aws_instance.app01.public_ip
}
output "website" {
  value      = "http://${aws_lb.main.dns_name}"
  depends_on = [terraform_data.configure]
}
output "target_group_arn" {
  value = aws_lb_target_group.tomcat.arn
}

