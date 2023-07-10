variable "ecssc_slack_channel_name" {
  default = "#alert-testing"
}

variable "ecssc_slack_webhook_url" {
  default = "https://api.slack.com/apps/qwerty/incoming-webhooks"
}

locals {
  all_account_root_arns = data.terraform_remote_state.organizations.outputs.all_account_root_arns
  all_account_ids       = data.terraform_remote_state.organizations.outputs.all_account_ids

}

######################################################################
######################################################################
######################################################################

# AWS events comes to default event bus. We defined a rule (and a role) to catch the events we want and gave our custom bus as a target (in aws_cloudwatch_event_target). 
# After that our custom bus calls own target (lambda function).  

resource "aws_cloudwatch_event_rule" "ecs_state_check_default" {
  name           = "ecs-state-check"
  event_bus_name = "default"
  event_pattern  = <<EOF
{
  "source": [
    "aws.ecs"
  ],
  "detail-type": [
    "ECS Task State Change"
    
  ]
}
EOF
}

resource "aws_cloudwatch_event_target" "ecs_state_check_default" {
  target_id = "ecs-sc-target-default"
  arn       = aws_cloudwatch_event_bus.ecs_state_check.arn
  rule      = aws_cloudwatch_event_rule.ecs_state_check_default.name
  role_arn  = aws_iam_role.ecs_state_check_target.arn
}

# IAM role for event bus target
data "aws_iam_policy_document" "ecs_sc_target_policy" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "events.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "ecs_state_check_target" {
  name = "ecs-sc-target-role"

  assume_role_policy = data.aws_iam_policy_document.ecs_sc_target_policy.json
}

data "aws_iam_policy_document" "put_events" {
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.ecs_state_check.arn]
  }
}

resource "aws_iam_role_policy" "put_events" {
  name   = "put_events_policy"
  role   = aws_iam_role.ecs_state_check_target.name
  policy = data.aws_iam_policy_document.put_events.json
}

######################################################################

resource "aws_ecr_repository" "ecs-sc" {
  name = "ecs-sc"
}

resource "aws_cloudwatch_event_bus" "ecs_state_check" {
  name = "ecs-state-check"
}

resource "aws_cloudwatch_event_rule" "ecs_state_check" {
  name           = "ecs-state-check"
  event_bus_name = aws_cloudwatch_event_bus.ecs_state_check.name
  event_pattern  = <<EOF
{
  "source": [
    "aws.ecs"
  ],
  "detail-type": [
    "ECS Task State Change"
  ]
}
EOF
}

#"ECS Container Instance State Change" can be added to detail-types

resource "aws_cloudwatch_event_target" "ecs_state_check" {
  target_id      = "ecs-sc-target"
  arn            = aws_lambda_function.ecs_state_check.arn
  rule           = aws_cloudwatch_event_rule.ecs_state_check.name
  event_bus_name = aws_cloudwatch_event_bus.ecs_state_check.name
}

data "aws_iam_policy_document" "ecs_state_check_policy_doc" {
  statement {
    sid    = "EnvAccess"
    effect = "Allow"
    actions = [
      "events:PutEvents"
    ]
    resources = [aws_cloudwatch_event_bus.ecs_state_check.arn]
    principals {
      type        = "AWS"
      identifiers = local.all_account_root_arns

    }
  }
}

resource "aws_cloudwatch_event_bus_policy" "ecs_state_check" {
  policy         = data.aws_iam_policy_document.ecs_state_check_policy_doc.json
  event_bus_name = aws_cloudwatch_event_bus.ecs_state_check.name
}

######################################################################
######################################################################
######################################################################

resource "aws_cloudwatch_log_group" "ecs_state_check" {
  name              = "/aws/lambda/ecs-state-check"
  retention_in_days = 14
}

# IAM role for Lambda

data "aws_iam_policy_document" "ecs_sc_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
        "ecs-tasks.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "ecs_sc_role" {
  name = "ecs-sc-role"

  assume_role_policy = data.aws_iam_policy_document.ecs_sc_policy.json
}

data "aws_iam_policy_document" "ecs_sc_policy_document" {

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ssm:GetParametersByPath",
      "ecs:Describe*",
      "ecr:GetAuthorizationToken",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:PutMetricData",
      "ecs:*", # Edit this line
      "iam:ListAccountAliases",
      "organizations:ListAccounts",
      "organizations:DescribeAccount"
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [for account_id in local.all_account_ids : "arn:aws:iam::${account_id}:role/ecs-api-access-cross-account-role"]
  }
}

resource "aws_iam_role_policy" "ecs_sc_policy" {
  name   = "ecs_sc_policy"
  role   = aws_iam_role.ecs_sc_role.name
  policy = data.aws_iam_policy_document.ecs_sc_policy_document.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_ecs_sc_role_policy_attach" {
  role       = aws_iam_role.ecs_sc_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Lambda
resource "aws_lambda_function" "ecs_state_check" {
  filename         = data.archive_file.ecs_state_check.output_path
  function_name    = "ecs-state-check"
  runtime          = "python3.9"
  handler          = "ecs-state-check.lambda_handler"
  role             = aws_iam_role.ecs_sc_role.arn
  source_code_hash = data.archive_file.ecs_state_check.output_base64sha256

  environment {
    variables = {
      ECSSC_SLACK_CHANNEL_NAME = var.ecssc_slack_channel_name
      ECSSC_SLACK_WEBHOOK_URL  = var.ecssc_slack_webhook_url
    }
  }
}

# Trigger
resource "aws_lambda_permission" "ecs_state_check" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_state_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecs_state_check.arn
}

data "archive_file" "ecs_state_check" {
  type        = "zip"
  source_file = "ecs-state-check/ecs-state-check.py"
  output_path = "ecs-state-check.zip"
}
