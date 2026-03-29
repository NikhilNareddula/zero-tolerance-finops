# 1. Register GitHub as a trusted Identity Provider in AWS
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's official cryptographic fingerprints
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# 2. Create the IAM Role for the GitHub Pipeline (The Bouncer)
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
            # CRITICAL: This physically locks the role to your exact GitHub repository
            # Format: repo:OWNER/REPO:ref:refs/heads/BRANCH or repo:OWNER/REPO:* for all branches
            "token.actions.githubusercontent.com:sub" : "repo:${var.repo_name}:*"
          }
        }
      }
    ]
  })
}

# 3. Create the Custom Least Privilege Policy (REPLACES ADMIN)
resource "aws_iam_policy" "github_actions_least_privilege" {
  name        = "ZeroTolerance-GitHubActions-Policy"
  description = "Strict permissions for GitHub Actions to build the FinOps project"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Block 1: The Application & Infrastructure Services
        Sid    = "ManageAppServices"
        Effect = "Allow"
        Action = [
          "s3:*",
          "lambda:*",
          "events:*",
          "sns:*",
          "ec2:*"   # Allows Terraform to build/tag test EC2 instances
        ]
        Resource = "*"
      },
      {
        # Block 2: The IAM Security Sandbox (The Senior Flex)
        Sid    = "ManageProjectRolesOnly"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PassRole",
          "iam:TagRole"
        ]
        # CRITICAL: This role can only create or edit OTHER roles that start with the name "ZeroTolerance"
        Resource = "arn:aws:iam::*:role/ZeroTolerance*"
      }
    ]
  })
}

# 4. Attach the NEW policy to your existing Bouncer Role
resource "aws_iam_role_policy_attachment" "github_actions_custom_attach" {
  role       = aws_iam_role.github_actions_role.id
  policy_arn = aws_iam_policy.github_actions_least_privilege.arn
}

# 5. Output the Role ARN so we can easily copy it into your YAML file
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "The ARN of the IAM role to use in your GitHub Actions workflow for OIDC authentication."
}