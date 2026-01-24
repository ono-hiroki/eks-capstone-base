variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "capstone-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "argocd_domain_name" {
  description = "Domain name for Argo CD (e.g., argocd.example.com)"
  type        = string
}

variable "app_domain_name" {
  description = "Domain name for the application (e.g., app.example.com)"
  type        = string
}

variable "hosted_zone_name" {
  description = "Route 53 hosted zone name (e.g., example.com)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "capstone"
    ManagedBy = "terraform"
  }
}
