terraform {
  backend "s3" {
    key            = "consul-ecs-cluster.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-state-lock"
  }
}
