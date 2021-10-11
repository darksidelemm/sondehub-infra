data "archive_file" "predict_updater" {
  type        = "zip"
  source_file = "predict_updater/lambda_function.py"
  output_path = "${path.module}/build/predict_updater.zip"
}

resource "aws_iam_role" "predict_updater" {
  path                 = "/service-role/"
  name                 = "predict-updater"
  assume_role_policy   = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {
            "Service": "lambda.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
    }]
}
EOF
  max_session_duration = 3600
}


resource "aws_iam_role_policy" "predict_updater" {
  name   = "predict_updater"
  role   = aws_iam_role.predict_updater.name
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "es:*",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "sqs:*",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "*"
        }
    ]
}
EOF
}


resource "aws_lambda_function" "predict_updater" {
  function_name                  = "predict_updater"
  handler                        = "lambda_function.predict"
  filename                       = "${path.module}/build/predict_updater.zip"
  source_code_hash               = data.archive_file.predict_updater.output_base64sha256
  publish                        = true
  memory_size                    = 256
  role                           = aws_iam_role.predict_updater.arn
  runtime                        = "python3.9"
  architectures                  = ["arm64"]
  timeout                        = 60
  reserved_concurrent_executions = 8
  environment {
    variables = {
      "ES" = aws_route53_record.es.fqdn
    }
  }
}


resource "aws_cloudwatch_event_rule" "predict_updater" {
  name        = "predict_updater"
  description = "predict_updater"

  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "predict_updater" {
  rule      = aws_cloudwatch_event_rule.predict_updater.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.predict_updater.arn
}

resource "aws_lambda_permission" "predict_updater" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.predict_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.predict_updater.arn
}

resource "aws_apigatewayv2_route" "predictions" {
  api_id             = aws_apigatewayv2_api.main.id
  api_key_required   = false
  authorization_type = "NONE"
  route_key          = "GET /predictions"
  target             = "integrations/${aws_apigatewayv2_integration.predictions.id}"
}

resource "aws_apigatewayv2_route" "reverse_predictions" {
  api_id             = aws_apigatewayv2_api.main.id
  api_key_required   = false
  authorization_type = "NONE"
  route_key          = "GET /predictions/reverse"
  target             = "integrations/${aws_apigatewayv2_integration.reverse_predictions.id}"
}

resource "aws_apigatewayv2_integration" "predictions" {
  api_id                 = aws_apigatewayv2_api.main.id
  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.predictions.arn
  timeout_milliseconds   = 30000
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "reverse_predictions" {
  api_id                 = aws_apigatewayv2_api.main.id
  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.reverse_predictions.arn
  timeout_milliseconds   = 30000
  payload_format_version = "2.0"
}

data "archive_file" "predictions" {
  type        = "zip"
  source_file = "predict/lambda_function.py"
  output_path = "${path.module}/build/predictions.zip"
}

data "archive_file" "reverse_predictions" {
  type        = "zip"
  source_file = "reverse-predict/lambda_function.py"
  output_path = "${path.module}/build/reverse-predict.zip"
}

resource "aws_lambda_function" "predictions" {
  function_name    = "predictions"
  handler          = "lambda_function.predict"
  filename         = "${path.module}/build/predictions.zip"
  source_code_hash = data.archive_file.predictions.output_base64sha256
  publish          = true
  memory_size      = 128
  role             = aws_iam_role.basic_lambda_role.arn
  runtime          = "python3.9"
  timeout          = 30
  architectures    = ["arm64"]
  environment {
    variables = {
      "ES" = "es.${local.domain_name}"
    }
  }
}
resource "aws_lambda_permission" "predictions" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.predictions.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.main.id}/*/*/predictions"
}


resource "aws_lambda_function" "reverse_predictions" {
  function_name    = "reverse-predictions"
  handler          = "lambda_function.predict"
  filename         = "${path.module}/build/reverse-predict.zip"
  source_code_hash = data.archive_file.reverse_predictions.output_base64sha256
  publish          = true
  memory_size      = 128
  role             = aws_iam_role.basic_lambda_role.arn
  runtime          = "python3.9"
  timeout          = 30
  architectures    = ["arm64"]
  environment {
    variables = {
      "ES" = "es.${local.domain_name}"
    }
  }
}
resource "aws_lambda_permission" "reverse_predictions" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reverse_predictions.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.main.id}/*/*/predictions/reverse"
}




resource "aws_ecs_task_definition" "tawhiri" {
  family = "tawhiri"
  container_definitions = jsonencode(
    [
      {
        command     = []
        cpu         = 0
        environment = []
        essential   = true
        image       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/tawhiri:latest"
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/tawhiri"
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
        mountPoints = [
          {
            containerPath = "/srv"
            sourceVolume  = "srv"
          },
        ]
        name = "tawhiri"
        portMappings = [
          {
            containerPort = 8000
            hostPort      = 8000
            protocol      = "tcp"
          },
        ]
        volumesFrom = []
      },
    ]
  )
  cpu                = "512"
  execution_role_arn = "arn:aws:iam::143841941773:role/ecsTaskExecutionRole"
  memory             = "1024"
  network_mode       = "awsvpc"
  requires_compatibilities = [
    "FARGATE",
  ]
  tags          = {}
  task_role_arn = "arn:aws:iam::143841941773:role/ecsTaskExecutionRole"


  volume {
    name = "srv"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.tawhiri.id
      root_directory          = "srv"
      transit_encryption      = "DISABLED"

      authorization_config {
        iam = "DISABLED"
      }
    }
  }
}

resource "aws_ecs_task_definition" "tawhiri_downloader" {
  family = "tawhiri-downloader"
  container_definitions = jsonencode(
    [
      {
        command = [
          "daemon",
        ]
        cpu = 0
        environment = [
          {
            name  = "TZ"
            value = "UTC"
          },
        ]
        essential = true
        image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/tawhiri-downloader:latest"
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/tawhiri-downloader"
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
        mountPoints = [
          {
            containerPath = "/srv"
            sourceVolume  = "srv"
          },
        ]
        name         = "tawhiri-downloader"
        portMappings = []
        volumesFrom  = []
      },
    ]
  )
  cpu                = "256"
  execution_role_arn = "arn:aws:iam::143841941773:role/ecsTaskExecutionRole"
  memory             = "512"
  network_mode       = "awsvpc"
  requires_compatibilities = [
    "FARGATE",
  ]
  tags          = {}
  task_role_arn = "arn:aws:iam::143841941773:role/ecsTaskExecutionRole"


  volume {
    name = "srv"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.tawhiri.id
      root_directory          = "srv"
      transit_encryption      = "DISABLED"

      authorization_config {
        iam = "DISABLED"
      }
    }
  }
}

resource "aws_ecs_task_definition" "tawhiri_ruaumoko" {
  family = "tawhiri-ruaumoko"
  container_definitions = jsonencode(
    [
      {
        cpu = 0
        entryPoint = [
          "/root/.local/bin/ruaumoko-download",
        ]
        environment = []
        essential   = true
        image       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/tawhiri:latest"
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/tawhiri-ruaumoko"
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
        mountPoints = [
          {
            containerPath = "/srv"
            sourceVolume  = "srv"
          },
        ]
        name         = "ruaumoko"
        portMappings = []
        volumesFrom  = []
      },
    ]
  )
  cpu                = "1024"
  execution_role_arn = "arn:aws:iam::143841941773:role/ecsTaskExecutionRole"
  memory             = "2048"
  network_mode       = "awsvpc"
  requires_compatibilities = [
    "FARGATE",
  ]
  tags          = {}
  task_role_arn = "arn:aws:iam::143841941773:role/ecsTaskExecutionRole"


  volume {
    name = "srv"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.tawhiri.id
      root_directory          = "srv"
      transit_encryption      = "DISABLED"

      authorization_config {
        iam = "DISABLED"
      }
    }
  }
}



resource "aws_efs_file_system" "tawhiri" {
  tags = {
    Name = "Tawhiri"
  }
  lifecycle_policy {
    transition_to_ia = "AFTER_7_DAYS"
  }
}

resource "aws_ecr_repository" "tawhiri" {
  name                 = "tawhiri"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
resource "aws_ecr_repository" "tawhiri_downloader" {
  name                 = "tawhiri-downloader"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

