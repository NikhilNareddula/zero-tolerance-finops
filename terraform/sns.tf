# 1. Create the Notification Hub (The Topic)
resource "aws_sns_topic" "remediation_alerts" {
  count = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  name = "zero-tolerance-finops-alerts"

  # --- THE FIX: Encrypt messages at rest using the free AWS managed key ---
  kms_master_key_id = "alias/aws/sns"
}

# 2. Subscribe Your Email to the Hub
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  topic_arn = aws_sns_topic.remediation_alerts.arn
  protocol  = "email"

  # This automatically pulls the email from your GitHub Secrets (TF_VAR_security_alert_email)
  endpoint = var.security_alert_email
}

