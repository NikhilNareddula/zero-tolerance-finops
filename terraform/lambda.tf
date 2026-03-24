# 1. Compress the Python code into a .zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/remediation.zip"
}

# 2. Create the AWS Lambda function
resource "aws_lambda_function" "remediation_lambda" {

 # tfsec:ignore:aws-lambda-enable-tracing
 # checkov:skip=CKV_AWS_50: X-Ray tracing adds unnecessary cost to a 2-second FinOps cron job.

  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "zero-tolerance-remediation"
  role             = aws_iam_role.remediation_role.arn
  handler          = "remediation.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # AWS  run this on a secure Linux container using Python 3.9
  runtime = "python3.9"
  timeout = 60 # Give it 60 seconds to run the account audit

  # Injecting the SNS Topic ARN dynamically
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.remediation_alerts.arn
    }
  }
}