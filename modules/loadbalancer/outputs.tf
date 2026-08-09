output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB (for alias records)"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.main.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (e.g. app/name/id) — required for CloudWatch alarm dimensions, NOT the same as the full ARN"
  value       = aws_lb.main.arn_suffix
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.web.arn
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (e.g. targetgroup/name/id) — required for CloudWatch alarm dimensions"
  value       = aws_lb_target_group.web.arn_suffix
}
