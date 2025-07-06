output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.agent.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.agent.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.agent.public_dns
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.agent.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.agent.zone_id
}

output "deployment_bucket_name" {
  description = "Name of the S3 deployment bucket"
  value       = aws_s3_bucket.deployments.bucket
}

output "deployment_bucket_arn" {
  description = "ARN of the S3 deployment bucket"
  value       = aws_s3_bucket.deployments.arn
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.agent.id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the first public subnet"
  value       = aws_subnet.public_1.id
}

output "application_url" {
  description = "URL to access the application directly"
  value       = "http://${aws_instance.agent.public_ip}"
}

output "load_balancer_url" {
  description = "URL to access the application via load balancer"
  value       = "http://${aws_lb.agent.dns_name}"
}

output "api_documentation_url" {
  description = "URL to access the API documentation"
  value       = "http://${aws_instance.agent.public_ip}/docs"
}

output "github_secrets" {
  description = "GitHub secrets configuration"
  value = {
    AWS_REGION              = var.aws_region
    EC2_INSTANCE_ID        = aws_instance.agent.id
    S3_DEPLOYMENT_BUCKET   = aws_s3_bucket.deployments.bucket
    ENVIRONMENT            = var.environment
  }
  sensitive = false
}
