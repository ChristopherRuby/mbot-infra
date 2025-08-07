output "instance_id" {
  description = "ID of the EC2 instance"
  value       = module.mbot_ec2.instance_id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.mbot_ec2.instance_public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance" 
  value       = module.mbot_ec2.instance_public_dns
}

output "application_url" {
  description = "URL to access the mbot application"
  value       = module.mbot_ec2.application_url
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i YOUR_KEY.pem ubuntu@${module.mbot_ec2.instance_public_ip}"
}