# 1. Compress the Python code into a .zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/remediation.zip"
}

# 2. Create the AWS Lambda function
resource "aws_lambda_function" "remediation_lambda" {
  count = var.is_enabled ? 1 : 0

  # --- FinOps Justified Checkov Skips ---
  # tfsec:ignore:aws-lambda-enable-tracing
  # checkov:skip=CKV_AWS_115: AWS Account has a strict limit of 10. Cannot reserve executions.
  # checkov:skip=CKV_AWS_50: X-Ray tracing adds unnecessary cost to a 2-second FinOps cron job.
  # checkov:skip=CKV_AWS_117: Lambda only interacts with public APIs (SNS, EC2); VPC deployment adds NAT costs.
  # checkov:skip=CKV_AWS_272: Code signing is overkill for a single-file script deployed via CI/CD.
  # checkov:skip=CKV_AWS_173: Env vars contain no sensitive data; default AWS managed key is sufficient.
  # checkov:skip=CKV_AWS_116: This is a stateless scheduled job; failed events do not need to be reprocessed via DLQ.

  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "zero-tolerance-remediation"
  role             = aws_iam_role.remediation_role[0].arn
  handler          = "remediation.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60


  # Injecting the SNS Topic ARN dynamically
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.remediation_alerts[0].arn
    }
  }
}