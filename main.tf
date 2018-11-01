terraform {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "current" {
  tags {
    Name = "${var.vpc_name}"

    # Optional tag to filter
    #BillingTeamName = "DevOps"

    # Optional tag to filter
    #Owner = "DevOps"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_ami" "ecs_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["*-amazon-ecs-optimized"]
  }
}

data "template_file" "user_data" {
  template = "${file("${path.module}/templates/default-user-data.sh.tpl")}"

  vars {
    aws_region          = "${data.aws_region.current.name}"
    ecs_cluster_name    = "${var.resource_name_prefix}-${random_id.entropy.hex}"
    consul_cluster_name = "${var.consul_cluster_tag_value}"
    consul_version      = "${var.consul_version}"
  }
}

resource "random_id" "entropy" {
  byte_length = 4
}

data "aws_subnet" "private" {
  count             = "${length(data.aws_availability_zones.available.names)}"
  vpc_id            = "${data.aws_vpc.current.id}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"

  tags {
    Tier = "Private"
  }
}

# Define security groups
resource "aws_security_group" "ecs_instance" {
  name_prefix = "${var.resource_name_prefix}-ecs-sg-${random_id.entropy.hex}"
  description = "Allows comminucation to and from our VPC"
  vpc_id      = "${data.aws_vpc.current.id}"

  ingress {
    description = "Allow SSH from the VPC range"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_vpc.current.cidr_block}"]
  }

  ingress {
    description = "TCP (8301) Consul gossip protocol"
    from_port   = 8301
    to_port     = 8301
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_vpc.current.cidr_block}"]
  }

  ingress {
    description = "UDP (8301) Consul gossip protocol"
    from_port   = 8301
    to_port     = 8301
    protocol    = "udp"
    cidr_blocks = ["${data.aws_vpc.current.cidr_block}"]
  }

  ingress {
    description = "TCP range for ECS container exposure"
    from_port   = 31678
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_vpc.current.cidr_block}"]
  }

  ingress {
    description = "UDP range for ECS container exposure"
    from_port   = 31678
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["${data.aws_vpc.current.cidr_block}"]
  }

  # ICMP
  ingress {
    description = "Allow ICMP from VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${data.aws_vpc.current.cidr_block}"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

/*
 * Create ECS cluster
 */
resource "aws_ecs_cluster" "this" {
  name = "${var.resource_name_prefix}-${random_id.entropy.hex}"
}

resource "aws_launch_configuration" "ecs_instance" {
  name_prefix                 = "${var.resource_name_prefix}-ecs-instance-${random_id.entropy.hex}"
  image_id                    = "${var.instance_ami != "" ? var.instance_ami : data.aws_ami.ecs_ami.id}"
  instance_type               = "${var.instance_type}"
  security_groups             = ["${aws_security_group.ecs_instance.id}"]
  iam_instance_profile        = "${aws_iam_instance_profile.ecs_instance.name}"
  key_name                    = "${var.aws_key_name}"
  associate_public_ip_address = false

  user_data = "${data.template_file.user_data.rendered}"

  root_block_device {
    volume_size = 30
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs_instance" {
  vpc_zone_identifier  = ["${data.aws_subnet.private.*.id}"]
  name                 = "${aws_launch_configuration.ecs_instance.name}"
  min_size             = "${var.ecs_instances_min}"
  max_size             = "${var.ecs_instances_max}"
  health_check_type    = "EC2"
  launch_configuration = "${aws_launch_configuration.ecs_instance.name}"

  tags = ["${concat(
              list(
                map("key", "Name", "value", format("%s-%s-%s", var.resource_name_prefix, "ecs-instance", random_id.entropy.hex), "propagate_at_launch", "true"),
                map("key", "io.opsgang.consul:clusters:ecs_nodes", "value", format("%s-%s-%s", var.resource_name_prefix, "ecs-instance", random_id.entropy.hex), "propagate_at_launch", "true"),
              ),
              var.tags_list,
            )
          }"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "ecs_instance_scale_up" {
  depends_on             = ["aws_autoscaling_group.ecs_instance"]
  autoscaling_group_name = "${aws_autoscaling_group.ecs_instance.name}"
  name                   = "${var.resource_name_prefix}-ecs-instance-scale-up-${random_id.entropy.hex}"
  adjustment_type        = "ChangeInCapacity"
  policy_type            = "SimpleScaling"
  cooldown               = 120
  scaling_adjustment     = 1
}

resource "aws_autoscaling_policy" "ecs_instance_scale_down" {
  depends_on             = ["aws_autoscaling_group.ecs_instance"]
  autoscaling_group_name = "${aws_autoscaling_group.ecs_instance.name}"
  name                   = "${var.resource_name_prefix}-ecs-instance-scale-down-${random_id.entropy.hex}"
  adjustment_type        = "ChangeInCapacity"
  policy_type            = "SimpleScaling"
  cooldown               = 240
  scaling_adjustment     = -1
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.resource_name_prefix}-ecs-instance-${random_id.entropy.hex}"
  path = "/consul/ecs/"
  role = "${aws_iam_role.ecs_instance.name}"
}

resource "aws_iam_role" "ecs_instance" {
  name               = "${var.resource_name_prefix}-ecs-instance-${random_id.entropy.hex}"
  path               = "/consul/ecs/"
  assume_role_policy = "${var.ecs_assume_role}"
}

resource "aws_iam_role_policy" "ecs_instance" {
  name = "${var.resource_name_prefix}-ecs-instance-${random_id.entropy.hex}"
  role = "${aws_iam_role.ecs_instance.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetAuthorizationToken",
        "ecr:GetDownloadUrlForLayer",
        "ecs:DeregisterContainerInstance",
        "ecs:DiscoverPollEndpoint",
        "ecs:Poll",
        "ecs:RegisterContainerInstance",
        "ecs:StartTask",
        "ecs:StartTelemetrySession",
        "ecs:Submit*",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

/*
 * Create EC2 IAM Instance Role and Policy
 */
resource "null_resource" "waiter" {
  depends_on = ["aws_iam_instance_profile.ecs_instance"]

  provisioner "local-exec" {
    command = "sleep 15"
  }
}
