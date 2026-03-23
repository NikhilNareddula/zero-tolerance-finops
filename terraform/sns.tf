# 1. Create the Notification Hub (The Topic)
resource "aws_sns_topic" "remediation_alerts" {
  name = "zero-tolerance-finops-alerts"
}

# 2. Subscribe Your Email to the Hub
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.remediation_alerts.arn
  protocol  = "email"

  # This automatically pulls the email from your GitHub Secrets (TF_VAR_security_alert_email)
  endpoint = var.security_alert_email
}