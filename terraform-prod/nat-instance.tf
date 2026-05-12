############################################################
# NAT Instance × 2 (AZ별 1개) + ASG
#
# fck-nat AMI 사용 (https://github.com/AndrewGuenther/fck-nat).
# Marketplace 가입 필요 없음 - 공개 AMI 로 배포됨.
# AMI 가 부팅 시 user_data 의 /etc/fck-nat.conf 를 읽어:
#   1) 자기 자신의 source/dest check 끔
#   2) 지정된 EIP 를 자기 instance 에 attach
#   3) 지정된 route table 의 0.0.0.0/0 을 자기 ENI 로 갱신
#   4) iptables MASQUERADE + ip_forward 설정
#
# ASG (desired=1) 가 instance 헬스 모니터링.
# 인스턴스가 죽으면 같은 AZ 에 새로 띄우고, 부팅 user_data 가 EIP/route 재셋업.
# Terraform 의 route table 은 0.0.0.0/0 route 를 inline 으로 안 가짐 -
# fck-nat 가 동적으로 관리 (lifecycle ignore_changes).
############################################################

# ── fck-nat AMI (ARM64) ─────────────────────────────────
data "aws_ami" "fck_nat" {
  most_recent = true
  owners      = ["568608671756"]   # fck-nat publisher account

  filter {
    name   = "name"
    values = ["fck-nat-al2023-*-arm64-ebs"]
  }
}

# ── EIP × 2 ─────────────────────────────────────────────
resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-eip-a" }
}

resource "aws_eip" "nat_c" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-eip-c" }
}

# ── Security Group (NAT instance) ───────────────────────
# private subnet 의 모든 트래픽을 받아서 인터넷으로 보냄
resource "aws_security_group" "nat_instance" {
  name        = "${local.name_prefix}-nat-instance-sg"
  description = "fck-nat instances - accept egress from private subnets"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "From private subnets - any protocol"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      aws_subnet.private_a.cidr_block,
      aws_subnet.private_c.cidr_block,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-nat-instance-sg" }
}

# ── IAM role: associate EIP, replace route, modify attribute ──
resource "aws_iam_role" "nat_instance" {
  name = "${local.name_prefix}-nat-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "nat_instance" {
  name = "${local.name_prefix}-nat-instance-policy"
  role = aws_iam_role.nat_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:AssociateAddress",
        "ec2:DisassociateAddress",
        "ec2:ReplaceRoute",
        "ec2:CreateRoute",
        "ec2:ModifyInstanceAttribute",
        "ec2:DescribeAddresses",
        "ec2:DescribeRouteTables",
        "ec2:DescribeNetworkInterfaces",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nat_instance_ssm" {
  role       = aws_iam_role.nat_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat_instance" {
  name = "${local.name_prefix}-nat-instance-profile"
  role = aws_iam_role.nat_instance.name
}

############################################################
# Launch Template - AZ-a
############################################################
resource "aws_launch_template" "nat_a" {
  name_prefix   = "${local.name_prefix}-nat-a-"
  image_id      = data.aws_ami.fck_nat.id
  instance_type = "t4g.nano"
  key_name      = var.key_pair_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.nat_instance.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.nat_instance.id]
    delete_on_termination       = true
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    cat > /etc/fck-nat.conf <<EOF
    eip_id=${aws_eip.nat_a.id}
    route_tables_ids=${aws_route_table.private_a.id}
    EOF
    systemctl restart fck-nat.service
  USERDATA
  )

  monitoring { enabled = true }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-nat-a"
      Role = "nat-instance"
    }
  }

  lifecycle { create_before_destroy = true }
}

############################################################
# Launch Template - AZ-c
############################################################
resource "aws_launch_template" "nat_c" {
  name_prefix   = "${local.name_prefix}-nat-c-"
  image_id      = data.aws_ami.fck_nat.id
  instance_type = "t4g.nano"
  key_name      = var.key_pair_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.nat_instance.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.nat_instance.id]
    delete_on_termination       = true
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    cat > /etc/fck-nat.conf <<EOF
    eip_id=${aws_eip.nat_c.id}
    route_tables_ids=${aws_route_table.private_c.id}
    EOF
    systemctl restart fck-nat.service
  USERDATA
  )

  monitoring { enabled = true }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-nat-c"
      Role = "nat-instance"
    }
  }

  lifecycle { create_before_destroy = true }
}

############################################################
# ASG × 2 - desired=1 each, EC2 health check
############################################################
resource "aws_autoscaling_group" "nat_a" {
  name_prefix         = "${local.name_prefix}-nat-a-"
  vpc_zone_identifier = [aws_subnet.public_a.id]
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  health_check_type         = "EC2"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.nat_a.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-nat-a"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_autoscaling_group" "nat_c" {
  name_prefix         = "${local.name_prefix}-nat-c-"
  vpc_zone_identifier = [aws_subnet.public_c.id]
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  health_check_type         = "EC2"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.nat_c.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-nat-c"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}
