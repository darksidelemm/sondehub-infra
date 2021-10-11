resource "aws_apigatewayv2_route" "sign_socket" {
  api_id             = aws_apigatewayv2_api.main.id
  api_key_required   = false
  authorization_type = "NONE"
  route_key          = "GET /sondes/websocket"
  target             = "integrations/${aws_apigatewayv2_integration.sign_socket.id}"
}

resource "aws_iam_role" "sign_socket" {
  name                 = "sign_socket"
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

data "archive_file" "sign_socket" {
  type        = "zip"
  source_file = "sign-websocket/lambda_function.py"
  output_path = "${path.module}/build/sign_socket.zip"
}

resource "aws_lambda_function" "sign_socket" {
  function_name    = "sign-websocket"
  handler          = "lambda_function.lambda_handler"
  filename         = "${path.module}/build/sign_socket.zip"
  source_code_hash = data.archive_file.sign_socket.output_base64sha256
  publish          = true
  memory_size      = 128
  role             = aws_iam_role.sign_socket.arn
  runtime          = "python3.9"
  timeout          = 10
  architectures    = ["arm64"]
}

resource "aws_lambda_permission" "sign_socket" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sign_socket.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.main.id}/*/*/sondes/websocket"
}

resource "aws_apigatewayv2_integration" "sign_socket" {
  api_id                 = aws_apigatewayv2_api.main.id
  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.sign_socket.arn
  timeout_milliseconds   = 30000
  payload_format_version = "2.0"
}


resource "aws_ecr_repository" "wsproxy" {
  name                 = "wsproxy"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}


// Subnet that is used to make discovery simple for the main ws server
resource "aws_subnet" "ws_main" {
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.31.134.0/28"

  tags = {
    Name = "wsmain"
  }
}

resource "aws_route_table_association" "ws_main" {
  subnet_id      = aws_subnet.ws_main.id
  route_table_id = aws_route_table.main.id
}

// so we need to ensure there is only as handful of IP addresses avaliable in the subnet, so we assign all the IPs to ENIs
resource "aws_network_interface" "ws_pad" {
  count     = 9
  subnet_id = aws_subnet.ws_main.id

  description = "Do not delete. Padding to limit addresses"
}

resource "aws_ecs_task_definition" "ws_reader" {
  family = "ws-reader"
  container_definitions = jsonencode(
    [
      {
        command = [
          "s3",
          "sync",
          "s3://sondehub-ws-config/",
          "/config/",
        ]
        cpu         = 0
        environment = []
        essential   = false
        image       = "amazon/aws-cli"
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/ws"
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
        mountPoints = [
          {
            containerPath = "/config"
            sourceVolume  = "config"
          },
        ]
        name         = "config"
        portMappings = []
        volumesFrom  = []
      },
      {
        command = []
        cpu     = 0
        dependsOn = [
          {
            condition     = "SUCCESS"
            containerName = "config"
          },
          {
            condition     = "SUCCESS"
            containerName = "config-move"
          },
        ]
        environment = []
        essential   = true
        image       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/wsproxy:latest"
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/ws"
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
        mountPoints = [
          {
            containerPath = "/mosquitto/config"
            sourceVolume  = "config"
          },
        ]
        name = "mqtt"
        portMappings = [
          {
            containerPort = 8080
            hostPort      = 8080
            protocol      = "tcp"
          },
          {
            containerPort = 8883
            hostPort      = 8883
            protocol      = "tcp"
          },
        ]
        ulimits = [
          {
            hardLimit = 50000
            name      = "nofile"
            softLimit = 30000
          },
        ]
        volumesFrom = []
      },
      {
        command = [
          "cp",
          "/config/mosquitto-reader.conf",
          "/config/mosquitto.conf",
        ]
        cpu = 0
        dependsOn = [
          {
            condition     = "SUCCESS"
            containerName = "config"
          },
        ]
        environment = []
        essential   = false
        image       = "alpine"
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/ws-reader"
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
        mountPoints = [
          {
            containerPath = "/config"
            sourceVolume  = "config"
          },
        ]
        name         = "config-move"
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
  task_role_arn = "arn:aws:iam::143841941773:role/ws"


  volume {
    name = "config"
  }
}

resource "aws_ecs_task_definition" "ws" {
  family = "ws"
  container_definitions = jsonencode(
    [
      {
        command = [
          "s3",
          "sync",
          "s3://sondehub-ws-config/",
          "/config/",
        ]
        cpu         = 0
        environment = []
        essential   = false
        image       = "amazon/aws-cli"
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/ws"
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
        mountPoints = [
          {
            containerPath = "/config"
            sourceVolume  = "config"
          },
        ]
        name         = "config"
        portMappings = []
        volumesFrom  = []
      },
      {
        cpu = 0
        dependsOn = [
          {
            condition     = "SUCCESS"
            containerName = "config"
          },
        ]
        environment = []
        essential   = true
        image       = "eclipse-mosquitto:2-openssl"
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/ws"
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
        mountPoints = [
          {
            containerPath = "/mosquitto/config"
            sourceVolume  = "config"
          },
        ]
        name = "mqtt"
        portMappings = [
          {
            containerPort = 8080
            hostPort      = 8080
            protocol      = "tcp"
          },
          {
            containerPort = 8883
            hostPort      = 8883
            protocol      = "tcp"
          },
          {
            containerPort = 1883
            hostPort      = 1883
            protocol      = "tcp"
          },
        ]
        ulimits = [
          {
            hardLimit = 50000
            name      = "nofile"
            softLimit = 30000
          },
        ]
        volumesFrom = []
      },
    ]
  )
  cpu                = "256"
  execution_role_arn = "arn:aws:iam::143841941773:role/ws"
  memory             = "512"
  network_mode       = "awsvpc"
  requires_compatibilities = [
    "FARGATE",
  ]
  tags          = {}
  task_role_arn = "arn:aws:iam::143841941773:role/ws"


  volume {
    name = "config"
  }
}

# service, reader, writer
# s3 config bucket
# iam roles
# security group
# reader autoscaling
