module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  name    = "eks-vpc"
  cidr    = "10.0.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  enable_nat_gateway = true
  map_public_ip_on_launch = true
}

resource "aws_ecr_repository" "cicd_test" {
  name                 = "cicd_test"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_security_group" "jenkins" {
  name        = "jenkins"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "jenkins"
  }
}

resource "aws_vpc_security_group_ingress_rule" "main" {
  security_group_id = aws_security_group.jenkins.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "jenkins" {
  security_group_id = aws_security_group.jenkins.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_vpc_security_group_egress_rule" "main" {
  security_group_id = aws_security_group.jenkins.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_iam_role" "ecr_pull" {
  name               = "ecr-pull-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "ecr_push_pull_policy" {
  name        = "ecr-push-pull-policy"
  description = "Allow GetAuthorizationToken and full push/pull to specific ECR repo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushAndPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "arn:aws:ecr:us-east-1:917024903431:repository/${aws_ecr_repository.cicd_test.name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_ecr_policy" {
  role       = aws_iam_role.ecr_pull.name
  policy_arn = aws_iam_policy.ecr_push_pull_policy.arn
}

resource "aws_iam_role" "ec2_ssm_ecr_role" {
  name               = "ec2-ssm-ecr-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_ssm" {
  role       = aws_iam_role.ec2_ssm_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "attach_ecr" {
  role       = aws_iam_role.ec2_ssm_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_instance_profile" "ec2_ssm_ecr_profile" {
  name = "ec2-ssm-ecr-profile"
  role = aws_iam_role.ec2_ssm_ecr_role.name
}

resource "aws_instance" "web" {
  instance_type = "t3.medium"
  ami           = "ami-00a929b66ed6e0de6"
  subnet_id     = module.vpc.public_subnets[0]
  iam_instance_profile = "ec2-ssm-ecr-profile"
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  user_data     = <<EOF
#!/bin/bash
sudo yum update
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum upgrade
sudo yum install java-17-amazon-corretto -y
sudo yum install jenkins -y
sudo yum install git -y
sudo yum install -y docker
sudo service docker start
sudo groupadd docker
sudo usermod -aG docker jenkins
newgrp docker
sudo systemctl enable jenkins
sudo systemctl start jenkins
EOF
  tags = {
    Name = "jenkins"
  }
}

output "vpc_id"       { value = module.vpc.vpc_id }
output "public_subnets"  { value = module.vpc.public_subnets }
output "private_subnets" { value = module.vpc.private_subnets }
