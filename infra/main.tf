# creating main vpc for jenkins and EKS cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  name    = var.vpc_name
  cidr    = "10.0.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  enable_nat_gateway = true
  map_public_ip_on_launch = true
}

# creating SG for Jenkins to open 8080 port
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


# creating role for Jenkins instance to get access for Secret Manager, Parameter Store and SSM connection
resource "aws_iam_role" "ec2_role" {
  name               = "ec2-role"
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

resource "aws_iam_role_policy_attachment" "attach_sm_full_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "attach_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "attach_ecr" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# creating ALB for Jenkins and SG for ALB
resource "aws_security_group" "alb" {
  name        = "jenkins-alb-sg"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "jenkins-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "lb_main" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "lb_main" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_lb" "jenkins" {
  name               = "jenkins-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
  enable_deletion_protection = false

  tags = {
    Name = "jenkins-alb"
  }
}

resource "aws_lb_target_group" "jenkins" {
  name        = "jenkins-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    protocol           = "HTTP"
    path               = "/"
    matcher            = "200-399"
    interval           = 30
    timeout            = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "jenkins-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins.id
  port             = 8080
}


# creating Jenkins instance
resource "aws_instance" "jenkins" {
  instance_type = "t3.medium"
  ami           = "ami-084568db4383264d4"
  subnet_id     = module.vpc.private_subnets[0]
  iam_instance_profile = "ec2-profile"
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  user_data     = templatefile("user_data.sh",
    {
      secret  = var.jenkins_secret_name
      parameter   = var.ssm_parameter_name
    }
  )
  tags = {
    Name = "jenkins"
  }
  depends_on = [
    module.vpc
  ]
}

# outputs for adding them to ClusterConfig
output "vpc_id"       { value = module.vpc.vpc_id }
output "public_subnets"  { value = module.vpc.public_subnets }
output "private_subnets" { value = module.vpc.private_subnets }
