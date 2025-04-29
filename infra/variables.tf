variable "vpc_name" {
  description = "Name of main vpc"
  type        = string
}

variable "ssm_parameter_name" {
  description = "Name of parameter with script for creating user"
  type        = string
}

variable "jenkins_secret_name" {
  description = "Secret name of credentials for Jenkins"
  type        = string
}
