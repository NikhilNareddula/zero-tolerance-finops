# Fetch current AWS Account ID and Region dynamically
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# 1. The Trust Policy (The Badge)
resource "aws_iam_role" "remediation_role" {
  count = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  name  = "zero-tolerance-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# 2. The Permissions Policy (What the Badge can do)
resource "aws_iam_role_policy" "remediation_policy" {
  count = var.is_enabled ? 1 : 0 # THE SAFETY SWITCH
  name  = "zero-tolerance-ec2-policy"
  role  = aws_iam_role.remediation_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # --- THE FIX: Describe actions require the "*" resource ---
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      },
      {
        # --- BLOCK 1: EC2 Business Logic (Quarantine) ---
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:CreateTags"
        ]
        # Securely locked to instances in this specific account and region
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
      },
      {
        # --- BLOCK 2: SNS Notifications ---
        Effect = "Allow"
        Action = "sns:Publish"
        # Locked to only publish to the topic we create in sns.tf
        Resource = aws_sns_topic.remediation_alerts[0].arn
      },
      {
        # --- BLOCK 3: CloudWatch Logging ---
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}