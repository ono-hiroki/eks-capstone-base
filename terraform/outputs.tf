# EKS Cluster
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

# kubeconfig
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# IRSA Role ARNs (used by bootstrap.sh)
output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller_irsa.iam_role_arn
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = module.external_secrets_irsa.iam_role_arn
}

output "demo_app_role_arn" {
  description = "IAM role ARN for demo app ServiceAccount"
  value       = module.demo_app_irsa.iam_role_arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for External DNS"
  value       = module.external_dns_irsa.iam_role_arn
}

# ACM Certificate ARNs (used by bootstrap.sh)
output "argocd_acm_certificate_arn" {
  description = "ACM certificate ARN for Argo CD"
  value       = aws_acm_certificate.argocd.arn
}

output "app_acm_certificate_arn" {
  description = "ACM certificate ARN for application"
  value       = aws_acm_certificate.app.arn
}

# Route 53 (used by bootstrap.sh)
output "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = data.aws_route53_zone.main.zone_id
}

# Domain names
output "argocd_domain_name" {
  description = "Argo CD domain name"
  value       = var.argocd_domain_name
}

output "app_domain_name" {
  description = "Application domain name"
  value       = var.app_domain_name
}

# URLs
output "argocd_url" {
  description = "Argo CD URL"
  value       = "https://${var.argocd_domain_name}"
}

output "app_url" {
  description = "Application URL"
  value       = "https://${var.app_domain_name}"
}

# ECR
output "ecr_repository_url" {
  description = "ECR repository URL pattern"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
