resource "aws_sns_topic" "ham_telem" {
  name            = "ham-telem"
  delivery_policy = <<EOF
{
  "http": {
    "defaultHealthyRetryPolicy": {
      "minDelayTarget": 5,
      "maxDelayTarget": 30,
      "numRetries": 100,
      "numMaxDelayRetries": 0,
      "numNoDelayRetries": 3,
      "numMinDelayRetries": 0,
      "backoffFunction": "linear"
    },
    "disableSubscriptionOverrides": false
  }
}
EOF
}


resource "aws_iam_role" "ham_sqs_to_elk" {
  path                 = "/service-role/"
  name                 = "ham_sqs-to-elk"
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


resource "aws_iam_role_policy" "ham_sqs_to_elk" {
  name   = "ham_sqs_to_elk"
  role   = aws_iam_role.ham_sqs_to_elk.name
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
        }
    ]
}
EOF
}

resource "aws_lambda_function" "ham_sqs_to_elk" {
  function_name                  = "ham-sqs-to-elk"
  handler                        = "ham_sqs_to_elk.lambda_handler"
  s3_bucket                      = aws_s3_bucket_object.lambda.bucket
  s3_key                         = aws_s3_bucket_object.lambda.key
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  publish                        = true
  memory_size                    = 128
  role                           = aws_iam_role.ham_sqs_to_elk.arn
  runtime                        = "python3.9"
  timeout                        = 5
  reserved_concurrent_executions = 100
  environment {
    variables = {
      "ES" = aws_route53_record.es.fqdn
    }
  }
  tags = {
    Name = "ham_sqs_to_elk"
  }
}

resource "aws_lambda_event_source_mapping" "ham_sqs_to_elk" {
  event_source_arn                   = aws_sqs_queue.ham_sqs_to_elk.arn
  function_name                      = aws_lambda_function.ham_sqs_to_elk.arn
  batch_size                         = 20
  maximum_batching_window_in_seconds = 15
}

resource "aws_sns_topic_subscription" "ham_sqs_to_elk" {
  topic_arn = aws_sns_topic.ham_telem.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.ham_sqs_to_elk.arn
}

resource "aws_sqs_queue" "ham_sqs_to_elk" {
  name                      = "ham-to-elk"
  receive_wait_time_seconds = 1
  message_retention_seconds = 1209600 # 14 days

  redrive_policy = jsonencode(
    {
      deadLetterTargetArn = aws_sqs_queue.ham_sqs_to_elk_dlq.arn
      maxReceiveCount     = 100
    }
  )
}

resource "aws_sqs_queue" "ham_sqs_to_elk_dlq" {
  name                      = "ham-to-elk-dlq"
  receive_wait_time_seconds = 1
  message_retention_seconds = 1209600 # 14 days

}

resource "aws_sqs_queue_policy" "ham_sqs_to_elk" {
  queue_url = aws_sqs_queue.ham_sqs_to_elk.id
  policy    = <<EOF
{
  "Version": "2008-10-17",
  "Id": "__default_policy_ID",
  "Statement": [
    {
      "Sid": "__owner_statement",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "SQS:*",
      "Resource": "${aws_sqs_queue.ham_sqs_to_elk.arn}"
    },
    {
      "Sid": "to-elk",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "SQS:SendMessage",
      "Resource": "${aws_sqs_queue.ham_sqs_to_elk.arn}",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "${aws_sns_topic.ham_telem.arn}"
        }
      }
    }
  ]
}
EOF
}