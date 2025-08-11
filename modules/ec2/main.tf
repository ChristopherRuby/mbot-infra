data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "mbot_chatbot" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.mbot_sg.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    perplexity_api_key = var.perplexity_api_key
    mongodb_uri        = var.mongodb_uri
    mongodb_database   = var.mongodb_database
    mongodb_collection = var.mongodb_collection
    github_repo        = var.github_repo
    domain_name        = var.domain_name
    ssl_email          = var.ssl_email
  }))

  tags = {
    Name        = "${var.project_name}-chatbot"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Elastic IP for the instance
resource "aws_eip" "mbot_eip" {
  instance = aws_instance.mbot_chatbot.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-eip"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_instance.mbot_chatbot]
}