# I output the Lambda ARN so other DevOps pipelines can trigger the 
# cost-center tagging evaluation on-demand if needed.
output "tag_remediation_lambda_arn" {
  description = "The ARN of the Lambda function that terminates untagged resources"
  value       = aws_lambda_function.remediation_lambda[0].arn
}

# I output the SNS Topic ARN so the Finance and Cloud Ops teams 
# can subscribe to alerts when an untagged resource is deleted.
output "billing_alerts_sns_arn" {
  description = "The ARN of the SNS topic for untagged resource deletion alerts"
  value       = aws_sns_topic.remediation_alerts[0].arn
}

# I output the IAM Role ARN for strict auditing. 
output "lambda_execution_role_arn" {
  description = "The IAM Role assumed by the FinOps tag remediation Lambda"
  value       = aws_iam_role.remediation_role[0].arn
}

# Output the Bouncer Rule
output "bouncer_eventbridge_arn" {
  description = "The ARN of the EventBridge rule catching pending EC2 instances"
  value       = aws_cloudwatch_event_rule.bouncer_rule[0].arn
}

# Output the Auditor Rule
output "auditor_eventbridge_arn" {
  description = "The ARN of the EventBridge rule running the daily audit"
  value       = aws_cloudwatch_event_rule.auditor_rule[0].arn
}