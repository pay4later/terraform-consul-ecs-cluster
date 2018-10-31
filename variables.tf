variable "vpc_name" {
  default     = "Default"
  description = "The name of the VPC ommiting the -vpc suffix"
}

variable "consul_cluster_tag_value" {
  description = "The value of the io.opsgang.consul:clusters:nodes tag describing your Consul cluster."
}

variable "consul_version" {
  default     = "1.3.0"
  description = "Version of Consul to install. Use semver, for example 0.8.4"
}

variable "instance_ami" {
  default     = ""
  type        = "string"
  description = "Provide AMI instance or use default to go with latest ECS optimized image"
}

variable "instance_type" {
  type        = "string"
  default     = "t2.micro"
  description = "Type of the instance to use for the Consul cluster nodes. See https://aws.amazon.com/ec2/instance-types/"
}

variable "ecs_instances_min" {
  type        = "string"
  description = "Minimum autoscale (number of EC2 ECS Instances)"
  default     = "2"
}

variable "ecs_instances_max" {
  type        = "string"
  description = "Maximum autoscale (number of EC2 ECS Instances)"
  default     = "3"
}

variable "aws_key_name" {
  description = "SSH keypair name for the VPN instance"
}

variable "tags" {
  description = "A map of tags to add to all resources"

  default = {
    BillingTeamName = "DevOps"
    Owner           = "DevOps"
    Project         = "Consul"
  }
}

variable "tags_list" {
  type = "list"

  default = [
    {
      key                 = "BillingTeamName"
      value               = "DevOps"
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = "DevOps"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "Consul"
      propagate_at_launch = true
    },
  ]
}

variable "resource_name_prefix" {
  description = "All the resources will be prefixed with the value of this variable"
  default     = "consul"
}

/*
 * Change if you know what you do
 */
variable "ec2_consul_policy" {
  type = "string"

  default = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": "ec2:DescribeInstances",
      "Resource": "*"
    }
  ]
}
EOF
}

/*
 * Allow an EC2 instances to assume a role
 */
variable "ec2_assume_role" {
  type = "string"

  default = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

/*
 * Allow an ECS cluster instances to assume a role
 */
variable "ecs_assume_role" {
  type = "string"

  default = <<EOF
{
"Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs.amazonaws.com",
          "ec2.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}
