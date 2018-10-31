output "ecs_cluster_id" {
  value = "${aws_ecs_cluster.this.id}"
}

output "ecs_cluster_name" {
  value = "${aws_ecs_cluster.this.name}"
}

output "consul_cluster_name" {
  value = "${format("%s-%s-%s", var.resource_name_prefix, "instance", random_id.entropy.hex)}"
}
