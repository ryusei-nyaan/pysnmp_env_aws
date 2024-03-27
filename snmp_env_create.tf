# 変数定義
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "key-name" {}

# AWS Provider
provider "aws" {
  region     = "ap-northeast-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

#VPC
resource "aws_vpc" "test-vpc" {
  cidr_block = "172.16.0.0/24"
  tags = {
    Name = "test-vpc"
  }
}

#パブリックサブネット
resource "aws_subnet" "test-public-subnet" {
  vpc_id                  = aws_vpc.test-vpc.id
  cidr_block              = "172.16.0.0/28"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "test-public-subnet"
  }
}

#プライベートサブネット
resource "aws_subnet" "test-private-subnet" {
  vpc_id            = aws_vpc.test-vpc.id
  cidr_block        = "172.16.0.16/28"
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = "test-private-subnet"
  }
}


#インターネットゲートウェイ
resource "aws_internet_gateway" "test-gateway" {
  vpc_id = aws_vpc.test-vpc.id
  tags = {
    Name = "test-gateway"
  }
}
#ルートテーブル
resource "aws_route_table" "test-route-table1" {
  vpc_id = aws_vpc.test-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test-gateway.id
  }
  tags = {
    Name = "test-route-table1"
  }
}

resource "aws_route_table" "test-route-table2" {
  vpc_id = aws_vpc.test-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.test-nat.id
  }
  tags = {
    Name = "test-route-table2"
  }
}

#NATゲートウェイ
resource "aws_nat_gateway" "test-nat" {
  allocation_id = aws_eip.test-eip.id
  subnet_id     = aws_subnet.test-public-subnet.id

  tags = {
    Name = "test-nat"
  }

  depends_on = [aws_internet_gateway.test-gateway]
}


#ルートテーブルとサブネットの紐付け
resource "aws_route_table_association" "test-association1" {
  subnet_id      = aws_subnet.test-public-subnet.id
  route_table_id = aws_route_table.test-route-table1.id
}

resource "aws_route_table_association" "test-association2" {
  subnet_id      = aws_subnet.test-private-subnet.id
  route_table_id = aws_route_table.test-route-table2.id
}


#セキュリティグループ作成
resource "aws_security_group" "test-security-group1" {
  name        = "test-security-group1"
  description = "TEST"
  vpc_id      = aws_vpc.test-vpc.id

  ingress {
    description = "SNMP"
    from_port   = 161
    to_port     = 161
    protocol    = "udp"
    cidr_blocks = ["172.16.0.16/28"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "test-security-group1"
  }
}

resource "aws_security_group" "test-security-group2" {
  name        = "test-security-group2"
  description = "TEST"
  vpc_id      = aws_vpc.test-vpc.id


  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "test-security-group2"
  }
}




#ENI
resource "aws_network_interface" "test-nw-interface-manager" {
  subnet_id       = aws_subnet.test-private-subnet.id
  private_ips     = ["172.16.0.20"]
  security_groups = [aws_security_group.test-security-group2.id]

}

resource "aws_network_interface" "test-nw-interface-agent" {
  subnet_id       = aws_subnet.test-public-subnet.id
  private_ips     = ["172.16.0.5"]
  security_groups = [aws_security_group.test-security-group1.id]
}

#elastic ip
resource "aws_eip" "test-eip" {
  domain = "vpc"
}


#EIC
resource "aws_ec2_instance_connect_endpoint" "manager-eic" {
  subnet_id = aws_subnet.test-private-subnet.id

  security_group_ids = [
    aws_security_group.test-security-group2.id,
  ]

}


#EC2
resource "aws_instance" "test-instance-manager" {
  ami               = "ami-0310b105770df9334"
  instance_type     = "t2.micro"
  availability_zone = "ap-northeast-1a"
  key_name          = var.key-name
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.test-nw-interface-manager.id

  }

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update
              sudo yum install -y net-snmp
              sudo yum install -y net-snmp-utils
              sudo yum install -y firewalld 
              sudo systemctl start firewalld.service
              sudo systemctl start snmpd
              sudo yum install -y pip
              sudo pip install pysnmp
              EOF
  tags = {
    Name = "test-instance-manager"
  }
}


resource "aws_instance" "test-instance-agent" {
  ami               = "ami-0310b105770df9334"
  instance_type     = "t2.micro"
  availability_zone = "ap-northeast-1a"
  key_name          = var.key-name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.test-nw-interface-agent.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update
              sudo yum install -y net-snmp
              sudo yum install -y net-snmp-utils
              sudo yum install -y firewalld 
              sudo systemctl start firewalld.service
              sudo firewall-cmd --permanent --add-port=161/udp
              sudo systemctl restart firewalld.service
              sudo bash -c 'echo view systemview included .1.3.6.1.2.1.25 >> /etc/snmp/snmpd.conf'
              sudo bash -c 'echo com2sec notConfigUser default public >> /etc/snmp/snmpd.conf'
              sudo bash -c 'echo group  notConfigGroup v2c  notConfigUser >> /etc/snmp/snmpd.conf'
              sudo systemctl start snmpd
              EOF
  tags = {
    Name = "test-instance-agent"
  }
}







