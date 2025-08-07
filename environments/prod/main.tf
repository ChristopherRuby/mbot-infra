terraform {
  backend "s3" {
    bucket = "mbot-infra-terraform-state-prod"
    key    = "prod/terraform.tfstate"
    region = "eu-west-3"  # Paris pour minimiser les coûts
  }
}

module "shared" {
  source = "../../shared"
  
  environment = "prod"
}

module "mbot_ec2" {
  source = "../../modules/ec2"

  project_name    = var.project_name
  environment     = var.environment
  instance_type   = var.instance_type
  key_name        = var.key_name
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  
  # Sensitive variables
  perplexity_api_key = var.perplexity_api_key
  mongodb_uri        = var.mongodb_uri
  mongodb_database   = var.mongodb_database
  mongodb_collection = var.mongodb_collection
  github_repo        = var.github_repo
}