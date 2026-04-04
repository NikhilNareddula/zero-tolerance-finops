# 1. Register GitHub as a trusted Identity Provider in AWS
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's official cryptographic fingerprints
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}

# 2. Create the IAM Role for the GitHub Pipeline (NO RESOURCE FIELDS HERE)
resource "aws_iam_role" "github_actions_role" {
  name = "ZeroTolerance-GitHubActions-Deployer"

  # The Rules: Only let YOUR specific repo assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          "StringEquals" = {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          }
          "StringLike" = {
            "token.actions.githubusercontent.com:sub" : "repo:${var.repo_name}:*"
          }
        }
      }
    ]
  })
}

# 3. The TRULY Strict Least Privilege Policy (AllowIAMRead moved here!)
resource "aws_iam_policy" "github_actions_least_privilege" {
  name        = "ZeroTolerance-GitHubActions-Policy"
  description = "Strict, zero-skip IAM policy for FinOps deployment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # --- 0. Self-Read Permission (Fixes the Refresh State Error) ---
      {
        Sid    = "AllowIAMRead"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:GetPolicy",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ZeroTolerance-GitHubActions-Deployer",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/ZeroTolerance-GitHubActions-Policy"
        ]
      },

      # --- 1. S3 State Management (Bucket Level) ---
      {
        Sid      = "S3StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::zero-tolerance-state-*"
      },
      # --- 2. S3 State Management (Object Level) ---
      {
        Sid      = "S3StateBucketObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::zero-tolerance-state-*/*"
      },
      {
        Sid      = "S3GlobalRead"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListAllMyBuckets"]
        Resource = "*"
      },

      # --- 3. EC2 Remediation (Strict ARN + Conditions) ---
      {
        Sid      = "EC2Discovery"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeTags", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      },
      {
        Sid      = "EC2Remediation"
        Effect   = "Allow"
        Action   = ["ec2:StopInstances", "ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" : "ZeroToleranceFinOps" }
        }
      },

      # --- 4. Lambda (Removed wildcard, explicit API actions) ---
      {
        Sid    = "ManageLambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:UpdateFunctionCode", "lambda:ListVersionsByFunction","lambda:GetPolicy",
          "lambda:UpdateFunctionConfiguration", "lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:GetFunctionCodeSigningConfig",
          "lambda:ListFunctions", "lambda:AddPermission", "lambda:RemovePermission", "lambda:ListTags", "lambda:TagResource"
        ]
        Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:zero-tolerance-*"
      },

      # --- 5. EventBridge (Removed wildcard, explicit API actions) ---
      {
        Sid    = "ManageEventBridge"
        Effect = "Allow"
        Action = [
          "events:PutRule", "events:DeleteRule", "events:DescribeRule",
          "events:PutTargets", "events:RemoveTargets", "events:ListTargetsByRule", "events:ListTagsForResource", "events:TagResource"
        ]
        Resource = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/zero-tolerance-*"
      },

      # --- 6. SNS (Removed wildcard, explicit API actions) ---
      {
        Sid    = "ManageSNS"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes",
          "sns:GetTopicAttributes", "sns:ListTopics", "sns:Subscribe",
          "sns:Unsubscribe", "sns:ListSubscriptionsByTopic", "sns:ListTagsForResource", "sns:TagResource", "sns:GetSubscriptionAttributes"
        ]
        Resource = "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:zero-tolerance-*"
      },

      # --- 7. IAM Role & Policy (Strict Account ID Binding) ---
      {
        Sid    = "ManageIAM"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:ListRoleTags",
          "iam:PassRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
          "iam:ListPolicyVersions", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListRolePolicies"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/zero-tolerance-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/zero-tolerance-*"
        ]
      },
      {
        Sid      = "IAMGlobalRead"
        Effect   = "Allow"
        Action   = ["iam:ListRoles", "iam:ListPolicies"]
        Resource = "*"
      },

      # --- 8. CloudWatch Logs for Lambda ---
      {
        Sid    = "ManageCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:ListLogGroups",
          "logs:PutRetentionPolicy", "logs:DescribeLogGroups", "logs:ListTagsForResource", "logs:TagResource"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/zero-tolerance-*"
      }
    ]
  })
}

# 4. Attachment
resource "aws_iam_role_policy_attachment" "github_actions_custom_attach" {
  role       = aws_iam_role.github_actions_role.id
  policy_arn = aws_iam_policy.github_actions_least_privilege.arn
}

# 5. Outputs
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "Copy this ARN to your GitHub Repo Variable: AWS_OIDC_ROLE_ARN"
}

output "github_actions_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github.arn
  description = "The ARN of the GitHub OIDC provider (useful for troubleshooting trust relationships)."
}