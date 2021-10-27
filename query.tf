

data "archive_file" "query" {
  type        = "zip"
  source_file = "query/lambda_function.py"
  output_path = "${path.module}/build/query.zip"
}










resource "aws_lambda_function" "get_sondes" {
  function_name    = "query"
  handler          = "lambda_function.get_sondes"
  filename         = "${path.module}/build/query.zip"
  source_code_hash = data.archive_file.query.output_base64sha256
  publish          = true
  memory_size      = 256
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






resource "aws_lambda_function" "get_telem" {
  function_name    = "get_telem"
  handler          = "lambda_function.get_telem"
  filename         = "${path.module}/build/query.zip"
  source_code_hash = data.archive_file.query.output_base64sha256
  publish          = true
  memory_size      = 256
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

resource "aws_lambda_function" "get_sites" {
  function_name    = "get_sites"
  handler          = "lambda_function.get_sites"
  filename         = "${path.module}/build/query.zip"
  source_code_hash = data.archive_file.query.output_base64sha256
  publish          = true
  memory_size      = 256
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

resource "aws_lambda_function" "get_listener_telemetry" {
  function_name    = "get_listener_telemetry"
  handler          = "lambda_function.get_listener_telemetry"
  filename         = "${path.module}/build/query.zip"
  source_code_hash = data.archive_file.query.output_base64sha256
  publish          = true
  memory_size      = 256
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





resource "aws_lambda_permission" "get_sondes" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_sondes.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.main.id}/*/*/sondes"
}

resource "aws_lambda_permission" "get_sites" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_sites.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.main.id}/*/*/sites"
}




resource "aws_lambda_permission" "get_telem" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_telem.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.main.id}/*/*/sondes/telemetry"
}
resource "aws_lambda_permission" "get_listener_telemetry" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_listener_telemetry.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.main.id}/*/*/listeners/telemetry"
}

resource "aws_apigatewayv2_route" "get_sondes" {
  api_id             = aws_apigatewayv2_api.main.id
  api_key_required   = false
  authorization_type = "NONE"
  route_key          = "GET /sondes"
  target             = "integrations/${aws_apigatewayv2_integration.get_sondes.id}"
}

resource "aws_apigatewayv2_route" "get_sites" {
  api_id             = aws_apigatewayv2_api.main.id
  api_key_required   = false
  authorization_type = "NONE"
  route_key          = "GET /sites"
  target             = "integrations/${aws_apigatewayv2_integration.get_sites.id}"
}





resource "aws_apigatewayv2_route" "get_telem" {
  api_id             = aws_apigatewayv2_api.main.id
  api_key_required   = false
  authorization_type = "NONE"
  route_key          = "GET /sondes/telemetry"
  target             = "integrations/${aws_apigatewayv2_integration.get_telem.id}"
}

resource "aws_apigatewayv2_route" "get_listener_telemetry" {
  api_id             = aws_apigatewayv2_api.main.id
  api_key_required   = false
  authorization_type = "NONE"
  route_key          = "GET /listeners/telemetry"
  target             = "integrations/${aws_apigatewayv2_integration.get_listener_telemetry.id}"
}




resource "aws_apigatewayv2_integration" "get_sondes" {
  api_id                 = aws_apigatewayv2_api.main.id
  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_sondes.arn
  timeout_milliseconds   = 30000
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "get_sites" {
  api_id                 = aws_apigatewayv2_api.main.id
  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_sites.arn
  timeout_milliseconds   = 30000
  payload_format_version = "2.0"
}




resource "aws_apigatewayv2_integration" "get_telem" {
  api_id                 = aws_apigatewayv2_api.main.id
  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_telem.arn
  timeout_milliseconds   = 30000
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "get_listener_telemetry" {
  api_id                 = aws_apigatewayv2_api.main.id
  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_listener_telemetry.arn
  timeout_milliseconds   = 30000
  payload_format_version = "2.0"
}
