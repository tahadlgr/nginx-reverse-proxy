terraform {
  cloud {
    hostname     = "app.terraform.io"
    organization = "lifemote-networks"

    workspaces {
      name = "exercise"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "terraform_remote_state" "organizations" {
  backend = "remote"

  config = {
    organization = "lifemote-networks"
    workspaces = {
      name = "organizations"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "subnet" {
  count  = 2
  vpc_id = aws_vpc.main.id
  #cidr_block = aws_vpc.main.cidr_block
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, 1 + count.index) ####(prefix,newbits,netnum)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

###Route table set up rules to determine where network traffic from our subnet is directed
###Directs the traffic to the internet gateaway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

resource "aws_route_table_association" "route_table_association" {
  count          = 2
  subnet_id      = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_ecs_cluster" "nginx-cluster" {
  name = "nginx-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

data "aws_ssm_parameter" "amazon_linux_2_latest" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

resource "aws_cloudwatch_log_group" "cw_group" {
  name = "nginx-cw-group"
}

resource "aws_launch_template" "ecs_launch_template" {
  name          = "ecs_launch_template"
  image_id      = data.aws_ssm_parameter.amazon_linux_2_latest.value
  instance_type = "t3.small"
  #update_default_version = true
  vpc_security_group_ids = [aws_security_group.sg.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
  user_data = base64encode(<<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.nginx-cluster.name} >> /etc/ecs/ecs.config
yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
yum install -y https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
yum install -y ec2-instance-connect
amazon-linux-extras install epel
EOF
  )
}

resource "aws_autoscaling_group" "asg" {
  name               = "asg"
  availability_zones = [data.aws_availability_zones.available.names[0]]
  #vpc_zone_identifier       = [aws_subnet.subnet.id]
  desired_capacity = 1
  min_size         = 1
  max_size         = 3

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }
}

resource "aws_ecr_repository" "nginx_exercise" {
  name = "nginx-exercise"
}

resource "aws_ecs_task_definition" "nginx_ec2" {
  family                   = "service-ec2"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.ecs_role.arn
  execution_role_arn       = aws_iam_role.task_execution.arn
  container_definitions = jsonencode([
    {
      "name" : "nginx",
      "image" : "${aws_ecr_repository.nginx_exercise.repository_url}:v2.0",
      "cpu" : 256,
      "memory" : 256,
      "essential" : true,
      "portMappings" : [
        {
          "containerPort" : 80,
          "hostPort" : 80
        }
      ]
      "healthcheck" : {
        "command" : ["CMD-SHELL", "wget -O /dev/null http://localhost || exit 1"],
        "interval" : 10,
        "timeout" : 2,
        "retries" : 2,
        "startPeriod" : 10
      }
      "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-group" : "${aws_cloudwatch_log_group.cw_group.name}",
          "awslogs-region" : "eu-central-1",
          "awslogs-stream-prefix" : "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "nginx-service" {
  name                               = "nginx-service"
  cluster                            = aws_ecs_cluster.nginx-cluster.id
  task_definition                    = aws_ecs_task_definition.nginx_ec2.arn
  launch_type                        = "EC2"
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0

  network_configuration {
    subnets         = [aws_subnet.subnet.*.id[0]]
    security_groups = [aws_security_group.sg.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.nginx.arn
  }
}

resource "aws_ecs_task_definition" "nginx_fargate" {
  family                   = "service-fargate"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  task_role_arn            = aws_iam_role.ecs_role.arn
  execution_role_arn       = aws_iam_role.task_execution.arn
  container_definitions = jsonencode([
    {
      "name" : "nginx-fargate",
      "image" : "${aws_ecr_repository.nginx_exercise.repository_url}:v4.5",
      "cpu" : 256,
      "memory" : 512,
      "essential" : true,
      "portMappings" : [
        {
          "containerPort" : 80,
          "hostPort" : 80
        }
      ]
      "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-group" : "${aws_cloudwatch_log_group.cw_group.name}",
          "awslogs-region" : "eu-central-1",
          "awslogs-stream-prefix" : "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "nginx-service-fargate" {
  name            = "nginx-service-fargate"
  cluster         = aws_ecs_cluster.nginx-cluster.id
  task_definition = aws_ecs_task_definition.nginx_fargate.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    assign_public_ip = true
    subnets          = [aws_subnet.subnet.*.id[0]]
    security_groups  = [aws_security_group.sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.nginx_lb_target_group.arn
    container_name   = "nginx-fargate"
    container_port   = 80
  }
}

