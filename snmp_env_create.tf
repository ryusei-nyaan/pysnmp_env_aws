# AWS Provider
provider "aws" {
  region     = "ap-northeast-1"
  access_key = ""
  secret_key = ""
}


#VPC
resource "aws_vpc" "test-vpc" {
  cidr_block = "172.16.0.0/24"
  tags = {
    Name = "test-vpc"
  }
}
#サブネット
resource "aws_subnet" "test-subnet" {
  vpc_id                  = aws_vpc.test-vpc.id
  cidr_block              = "172.16.0.0/28"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "test-subnet"
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
resource "aws_route_table" "test-route-table" {
  vpc_id = aws_vpc.test-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test-gateway.id
  }
  tags = {
    Name = "test-route-table"
  }
}


#ルートテーブルとサブネットの紐付け
resource "aws_route_table_association" "test-association" {
  subnet_id      = aws_subnet.test-subnet.id
  route_table_id = aws_route_table.test-route-table.id
}

#セキュリティグループ作成
resource "aws_security_group" "test-security-group" {
  name        = "test-security-group"
  description = "TEST"
  vpc_id      = aws_vpc.test-vpc.id

  ingress {
    description = "SNMP"
    from_port   = 161
    to_port     = 161
    protocol    = "udp"
    cidr_blocks = ["172.16.0.0/28"]
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
    Name = "test-security-group"
  }
}


#ENI
resource "aws_network_interface" "test-nw-interface-manager" {
  subnet_id       = aws_subnet.test-subnet.id
  private_ips     = ["172.16.0.4"]
  security_groups = [aws_security_group.test-security-group.id]

}

resource "aws_network_interface" "test-nw-interface-agent" {
  subnet_id       = aws_subnet.test-subnet.id
  private_ips     = ["172.16.0.5"]
  security_groups = [aws_security_group.test-security-group.id]
}



#EC2
resource "aws_instance" "test-instance-manager" {
  ami               = "ami-0310b105770df9334"
  instance_type     = "t2.micro"
  availability_zone = "ap-northeast-1a"
  key_name          = "key-name"
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
  key_name          = "key-name"

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







