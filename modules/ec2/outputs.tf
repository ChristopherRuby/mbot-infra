output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.mbot_chatbot.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.mbot_chatbot.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.mbot_chatbot.public_dns
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.mbot_sg.id
}

output "application_url" {
  description = "URL to access the mbot application"
  value       = "http://${aws_instance.mbot_chatbot.public_ip}"
}