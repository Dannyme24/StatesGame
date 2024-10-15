terraform {
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 5.0"
      }
    }

    required_version = ">= 1.2.0"
}

provider "aws" {
    region = "us-east-1"
  
}


#####Backend#####

#Lambda Function
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam-for-lambda" {
  name               = "iam-for-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "archive_file" "backend-payload" {
    type        = "zip"
    source_file = "./backend/index.mjs"
    output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "backend-function" {
    filename      = "lambda_function_payload.zip"
    function_name = "StateGameBackend"
    role          = aws_iam_role.iam-for-lambda.arn
    handler       = "index.handler"

    source_code_hash = data.archive_file.backend-payload.output_base64sha256

    runtime = "nodejs18.x"
}

#BackendApi
resource "aws_api_gateway_rest_api" "backend-api" {
    name = "StateGameApi"
}

data "aws_api_gateway_resource" "backend-api-resource" {
    rest_api_id = aws_api_gateway_rest_api.backend-api.id
    path = "/"
}

/*resource "aws_api_gateway_resource" "backend-api-resource" {
    parent_id   = aws_api_gateway_rest_api.backend-api.root_resource_id
    path_part   = "."
    rest_api_id = aws_api_gateway_rest_api.backend-api.id
}*/

resource "aws_api_gateway_method" "backend-api-method" {
    authorization = "NONE"
    http_method = "POST"
    resource_id = data.aws_api_gateway_resource.backend-api-resource.id
    rest_api_id = aws_api_gateway_rest_api.backend-api.id
}

resource "aws_api_gateway_integration" "backend-api-lambdaintegration" {
    rest_api_id = aws_api_gateway_rest_api.backend-api.id
    resource_id = data.aws_api_gateway_resource.backend-api-resource.id
    http_method = aws_api_gateway_method.backend-api-method.http_method
    integration_http_method = "POST"
    type = "AWS"
    uri = aws_lambda_function.backend-function.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda" {
    statement_id  = "AllowExecutionFromAPIGateway"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.backend-function.function_name
    principal     = "apigateway.amazonaws.com"

    # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
    source_arn = "arn:aws:execute-api:us-east-1:${var.accountId}:${aws_api_gateway_rest_api.backend-api.id}/*/${aws_api_gateway_method.backend-api-method.http_method}${data.aws_api_gateway_resource.backend-api-resource.path}"
}

resource "aws_api_gateway_method_response" "method-response-200" {
    rest_api_id = aws_api_gateway_rest_api.backend-api.id
    resource_id = data.aws_api_gateway_resource.backend-api-resource.id
    http_method = aws_api_gateway_method.backend-api-method.http_method
    status_code = "200"

    response_parameters = {
      "method.response.header.Access-Control-Allow-Origin" = true
    }
}

resource "aws_api_gateway_integration_response" "backend-api-integration-response" {
    rest_api_id = aws_api_gateway_rest_api.backend-api.id
    resource_id = data.aws_api_gateway_resource.backend-api-resource.id
    http_method = aws_api_gateway_method.backend-api-method.http_method
    status_code = aws_api_gateway_method_response.method-response-200.status_code

    response_parameters = {
      "method.response.header.Access-Control-Allow-Origin" = "'*'"
    }

    response_templates = {
      "application/json" = null
    }

    depends_on = [ aws_api_gateway_integration.backend-api-lambdaintegration ]
}

resource "aws_api_gateway_deployment" "backend-api-deployment" {
    rest_api_id = aws_api_gateway_rest_api.backend-api.id

    lifecycle {
      create_before_destroy = true
    }

    depends_on = [ aws_api_gateway_integration_response.backend-api-integration-response,
                   aws_api_gateway_method_response.method-response-200 ]
    
}

resource "aws_api_gateway_stage" "backend-api-stage" {
  deployment_id = aws_api_gateway_deployment.backend-api-deployment.id
  rest_api_id   = aws_api_gateway_rest_api.backend-api.id
  stage_name    = "staging"
  
}

#####Site#####
resource "aws_amplify_app" "example" {
  name       = "statesGameFrontend"

  custom_rule {
    source = "/<*>"
    status = "404"
    target = "/index.html"
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.example.id
  branch_name = "staging"

  stage     = "PRODUCTION"

  environment_variables = {
    REACT_APP_API_SERVER = "https://api.example.com"
  }
}

resource "aws_s3_bucket" "statesGameBucket" {
  bucket = "statesgamebucket"
}

data "archive_file" "frontend-payload" {
  type        = "zip"
  output_path = "amplify_payload.zip"
  source_dir  = "site/"
}

resource "aws_s3_object" "upload-frontend-payload" {
  bucket = aws_s3_bucket.statesGameBucket.id
  key = "sitefiles.zip"
  source = "amplify_payload.zip"

  depends_on = [ data.archive_file.backend-payload, aws_s3_bucket.statesGameBucket ]
}

resource "aws_s3_bucket_ownership_controls" "enable-acl" {
  bucket = aws_s3_bucket.statesGameBucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "null_resource" "run-deploy" {
  provisioner "local-exec" {
    command = "aws amplify start-deployment --app-id $APP_ID --branch-name $BRANCH_NAME --source-url $SOUCE_URL"

    environment = {
      APP_ID = aws_amplify_app.example.id,
      BRANCH_NAME = aws_amplify_branch.master.branch_name
      SOUCE_URL = "s3://statesgamebucket/sitefiles.zip"

    }
  }

  depends_on = [ aws_s3_object.upload-frontend-payload, aws_amplify_branch.master ]
}

