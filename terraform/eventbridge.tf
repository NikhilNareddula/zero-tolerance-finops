# ==========================================
# 1. THE BOUNCER (Event-Driven Trigger)
# ==========================================
resource "aws_cloudwatch_event_rule" "bouncer_rule" {
  count       = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  name        = "zero-tolerance-bouncer"
  description = "Triggers when a new EC2 instance starts up"

  # Listens for the exact moment an instance enters the 'pending' state
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["pending"]
    }
  })
}

resource "aws_cloudwatch_event_target" "bouncer_target" {
  count     = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  rule      = aws_cloudwatch_event_rule.bouncer_rule[0].name
  target_id = "TriggerBouncerLambda"
  arn       = aws_lambda_function.remediation_lambda[0].arn
}

# Resource-Based Policy: Explicitly allow the Bouncer rule to invoke the Lambda
resource "aws_lambda_permission" "allow_bouncer" {
  count         = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  statement_id  = "AllowExecutionFromEventBridgeBouncer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation_lambda[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.bouncer_rule[0].arn
}

# ==========================================
# 2. THE AUDITOR (Scheduled Trigger)
# ==========================================
resource "aws_cloudwatch_event_rule" "auditor_rule" {
  count       = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  name        = "zero-tolerance-auditor"
  description = "Runs daily account audit at 2:30 AM UTC"
  # Runs daily account audit at 8:00 AM IST (2:30 AM UTC)
  schedule_expression = "cron(30 2 * * ? *)"
}

resource "aws_cloudwatch_event_target" "auditor_target" {
  count     = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  rule      = aws_cloudwatch_event_rule.auditor_rule[0].name
  target_id = "TriggerAuditorLambda"
  arn       = aws_lambda_function.remediation_lambda[0].arn
}

# Resource-Based Policy: Explicitly allow the Auditor rule to invoke the Lambda
resource "aws_lambda_permission" "allow_auditor" {
  count         = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  statement_id  = "AllowExecutionFromEventBridgeAuditor"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation_lambda[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auditor_rule[0].arn
}