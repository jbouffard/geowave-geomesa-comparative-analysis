#
# ECS Resources
#

# ECS cluster is only a name that ECS machines may join
resource "aws_ecs_cluster" "ca" {

  lifecycle {
    create_before_destroy = true
  }

  name = "${var.ecs_cluster_name}"
}

# Template for container definition, allows us to inject environment
data "template_file" "ecs_ca_task" {
  template = "${file("${path.module}/containers.json")}"

  vars {
    geowave_zookeeper = "${var.geowave_zookeeper}",
    geomesa_zookeeper = "${var.geomesa_zookeeper}"
  }
}

# Allows resource sharing among multiple containers
resource "aws_ecs_task_definition" "ca" {
  family                = "benchmarking"
  container_definitions = "${data.template_file.ecs_ca_task.rendered}"
}

# Defines running an ECS task as a service
resource "aws_ecs_service" "benchmarking" {
  name                               = "BenchmarkService"
  cluster                            = "${aws_ecs_cluster.ca.id}"
  task_definition                    = "${aws_ecs_task_definition.ca.family}:${aws_ecs_task_definition.ca.revision}"
  desired_count                      = "${var.desired_benchmark_instance_count}"
  # TODO: this needs to be managed
  iam_role                           = "${aws_iam_role.ecs_service_role.id}"

  load_balancer {
    elb_name       = "${aws_elb.ca.name}"
    container_name = "benchmark_service"
    container_port = 7070
  }
  
  depends_on = ["aws_iam_role_policy.ecs_service_role_policy"]
}

# Load balance among all running containers
resource "aws_elb" "ca" {
  subnets         = ["${var.subnet_id}"]

  listener {
    lb_port = 80
    lb_protocol       = "HTTP"
    instance_port     = 80
    instance_protocol = "HTTP"
  }

  cross_zone_load_balancing   = false

  tags {
    Name        = "Comparative Analysis ELB"
  }
}

#
# AutoScaling resources
#

# Defines a launch configuration for ECS worker, associates it with our cluster
resource "aws_launch_configuration" "ecs" {
  name = "ECS ${var.ecs_cluster_name}"
  image_id             = "${var.aws_ecs_ami}"
  instance_type        = "${var.ecs_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.ecs.id}"

  # TODO: is there a good way to make the key configurable sanely?
  key_name             = "${var.ec2_key}"
  associate_public_ip_address = true
  user_data = "#!/bin/bash\necho ECS_CLUSTER='${var.ecs_cluster_name}' > /etc/ecs/ecs.config"
}

# Auto-scaling group for ECS workers
resource "aws_autoscaling_group" "ecs" {
  lifecycle {
    create_before_destroy = true
  }

  # Explicitly linking ASG and launch configuration by name
  # to force replacement on launch configuration changes.
  name = "${aws_launch_configuration.ecs.name}"

  launch_configuration      = "${aws_launch_configuration.ecs.name}"
  health_check_grace_period = 600
  health_check_type         = "EC2"
  desired_capacity          = "${var.desired_benchmark_instance_count}"
  min_size                  = "${var.desired_benchmark_instance_count}"
  max_size                  = "${var.desired_benchmark_instance_count}"
  vpc_zone_identifier       = ["${var.subnet_id}"]

  tag {
    key                 = "Name"
    value               = "ECS Comparative Analysis"
    propagate_at_launch = true
  }
}


# Create roles to allow ECS hosts to call ECS API
resource "aws_iam_role" "ecs_host_role" {
  name = "ecs_host_role"
  assume_role_policy = "${file("${path.module}/policies/ecs-role.json")}"
}

resource "aws_iam_role_policy" "ecs_instance_role_policy" {
  name = "ecs_instance_role_policy"
  policy = "${file("${path.module}/policies/ecs-instance-role-policy.json")}"
  role = "${aws_iam_role.ecs_host_role.id}"
}

resource "aws_iam_role" "ecs_service_role" {
  name = "ecs_service_role"
  assume_role_policy = "${file("${path.module}/policies/ecs-role.json")}"
}

resource "aws_iam_role_policy" "ecs_service_role_policy" {
  name = "ecs_service_role_policy"
  policy = "${file("${path.module}/policies/ecs-service-role-policy.json")}"
  role = "${aws_iam_role.ecs_service_role.id}"
}

resource "aws_iam_instance_profile" "ecs" {
  path = "/"
  roles = ["${aws_iam_role.ecs_host_role.name}"]
}
