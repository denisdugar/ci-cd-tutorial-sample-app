module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  name    = "eks-vpc"
  cidr    = "10.0.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  enable_nat_gateway = true
}

resource "aws_efs_file_system" "jenkins_efs" {
  creation_token   = "jenkins-efs"
  performance_mode = "generalPurpose"
  encrypted        = true
  tags = {
    Name = "jenkins-efs"
  }
}

resource "aws_security_group" "efs_sg" {
  name        = "efs-sg"
  description = "Allow NFS access for EFS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_mount_target" "jenkins_mount_target_a" {
  file_system_id  = aws_efs_file_system.jenkins_efs.id
  subnet_id       = module.vpc.public_subnets[0]
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_efs_mount_target" "jenkins_mount_target_b" {
  file_system_id  = aws_efs_file_system.jenkins_efs.id
  subnet_id       = module.vpc.public_subnets[1]
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_efs_access_point" "example" {
  file_system_id = aws_efs_file_system.jenkins_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/jenkins"

    creation_info {
      owner_gid    = 1000
      owner_uid    = 1000
      permissions  = "0777"
    }
  }
}

output "vpc_id"       { value = module.vpc.vpc_id }
output "public_subnets"  { value = module.vpc.public_subnets }
output "private_subnets" { value = module.vpc.private_subnets }
output "efs_id" { value = aws_efs_file_system.jenkins_efs.id }
output "efs_ap_id" { value = aws_efs_access_point.example.id }
