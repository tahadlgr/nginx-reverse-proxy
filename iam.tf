data "aws_iam_policy_document" "ec2_access_policy" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "ec2.amazonaws.com",
        "ecs-tasks.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ssm_role_policy_attach" {
  role       = aws_iam_role.ecs_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_role_policy_attach" {
  role       = aws_iam_role.ecs_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role" "ecs_role" {
  name = "nginx-ecs-role"

  assume_role_policy = data.aws_iam_policy_document.ec2_access_policy.json
}

data "aws_iam_policy_document" "ecs_service" {

  statement {
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeregisterContainerInstance",
      "ecs:DescribeContainerInstances",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:RegisterContainerInstance",
      "ecs:StartTelemetrySession",
      "ecs:Submit*",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetAuthorizationToken",
      "sts:AssumeRole"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_service" {
  name   = "nginx-ecs-service"
  role   = aws_iam_role.ecs_role.name
  policy = data.aws_iam_policy_document.ecs_service.json
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  role = aws_iam_role.ecs_role.name
}

data "aws_iam_policy_document" "cw_logs" {
  statement {
    effect = "Allow"

    actions = [
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:PutMetricData",
      "ec2:DescribeTags",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutSubscriptionFilter",
      "logs:PutLogEvents",
    ]
    resources = ["*"]

  }
}

resource "aws_iam_role_policy" "cw_logs" {
  name = "cw-logs"

  role   = aws_iam_role.ecs_role.name
  policy = data.aws_iam_policy_document.cw_logs.json
}

data "aws_iam_policy_document" "ecs_cw_execution" {
  statement {
    effect = "Allow"

    actions = [
      "ecs:CreateCluster",
      "ecs:DeregisterContainerInstance",
      "ecs:DescribeContainerInstances",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:RegisterContainerInstance",
      "ecs:StartTelemetrySession",
      "ecs:Submit*",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetAuthorizationToken",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:PutMetricData",
      "ec2:DescribeTags",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutSubscriptionFilter",
      "logs:PutLogEvents",
    ]
    resources = ["*"]

  }
}

resource "aws_iam_role" "task_execution" {
  name = "task-execution-role"

  assume_role_policy = data.aws_iam_policy_document.ec2_access_policy.json
}

resource "aws_iam_role_policy" "cw_logs_execution" {
  name = "cw-logs-execution"

  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.ecs_cw_execution.json
}

### Cloud Watch Metrics for Monitoring 

data "aws_iam_policy_document" "cw_metrics" {
  statement {
    effect = "Allow"

    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetInsightRuleReport",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]

  }
}

resource "aws_iam_role_policy" "cw_metrics" {
  name = "cw-metrics"

  role   = aws_iam_role.ecs_role.id
  policy = data.aws_iam_policy_document.cw_metrics.json
}

resource "aws_iam_role_policy" "cw_metrics_execution" {
  name = "cw-metrics-execution"

  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.cw_metrics.json
}

data "aws_iam_policy_document" "cross_account_observability" {
  statement {
    effect = "Allow"

    actions = [
      "oam:ListSinks",
      "oam:ListAttachedLinks"
    ]
    resources = ["*"]

  }
}

resource "aws_iam_role_policy" "cross_account_observability" {
  name = "cross-account-observability"

  role   = aws_iam_role.ecs_role.id
  policy = data.aws_iam_policy_document.cross_account_observability.json
}