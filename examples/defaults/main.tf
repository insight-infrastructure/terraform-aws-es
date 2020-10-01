variable "aws_region" {
  default = "us-east-1"
}

provider "aws" {
  region = var.aws_region
}

resource "random_pet" "this" {
  length = 2
}

module "defaults" {
  source      = "../.."
  id          = random_pet.this.id
  domain_name = "insight-infra.net"
}
