variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "mbot"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "AWS Key Pair name for SSH access"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Sensitive variables - to be provided via terraform.tfvars or environment variables
variable "perplexity_api_key" {
  description = "Perplexity API key"
  type        = string
  sensitive   = true
}

variable "mongodb_uri" {
  description = "MongoDB connection URI"
  type        = string
  sensitive   = true
}

variable "mongodb_database" {
  description = "MongoDB database name"
  type        = string
  default     = "sample_mflix"
}

variable "mongodb_collection" {
  description = "MongoDB collection name"
  type        = string
  default     = "movies"
}

variable "github_repo" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/ChristopherRuby/mbot.git"
}