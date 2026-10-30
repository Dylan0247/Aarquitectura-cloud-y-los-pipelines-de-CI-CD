data "aws_instances" "web" {
  instance_tags = {
    "aws:autoscaling:groupName" = aws_autoscaling_group.web.name
  }
  instance_state_names = ["running"]
  depends_on           = [aws_autoscaling_group.web]
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.web.name
}

output "instance_public_ips" {
  description = "Instantanea de IPs en ejecucion; renovar tras finalizar el instance refresh."
  value       = data.aws_instances.web.public_ips
}

output "instance_ids" {
  value = data.aws_instances.web.ids
}

output "ssh_key_pair_name" {
  value = aws_key_pair.web.key_name
}

output "asg_public_subnet_ids" {
  value = slice(aws_subnet.public_subnets[*].id, 0, 2)
}

output "alb_url" {
  value = "http://${aws_lb.web.dns_name}"
}

output "web_target_group_arn" {
  value = aws_lb_target_group.web.arn
}

output "static_bucket_name" {
  value = aws_s3_bucket.static.id
}

output "static_object_uri" {
  value = "s3://${aws_s3_bucket.static.id}/${aws_s3_object.index.key}"
}
