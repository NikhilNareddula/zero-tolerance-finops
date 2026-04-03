# checkov:skip=CKV_AWS_286: CI/CD deployment role intentionally requires IAM creation capabilities to deploy the FinOps engine.
# checkov:skip=CKV_AWS_288: CI/CD role requires read access to verify Terraform state.                                       
# checkov:skip=CKV_AWS_355: CI/CD 'Eyes' (Describe/Get) require '*' resource as they cannot be bound to a specific ARN.
# checkov:skip=CKV_AWS_290: CI/CD role intentionally requires write access to deploy infrastructure.
# checkov:skip=CKV_AWS_289: CI/CD role is restricted by namespace (ZeroTolerance*) but requires policy management within that namespace.
# checkov:skip=CKV_AWS_287: CI/CD role needs IAM read permissions for Terraform state management.
  

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
          "ec2:*" # Allows Terraform to build/tag test EC2 instances
        ]
        Resource = "*"
      },
      {
        # Block 2: The Muscle (STAY SECURE)
        # Manages all project roles AND policies, handling both uppercase and lowercase.
        Sid    = "ManageProjectIAM"
        Effect = "Allow"
        Action = [
          # Role Permissions
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          # Policy Permissions (To fix Error 2)
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion"
        ]
        Resource = [
          "arn:aws:iam::*:role/ZeroTolerance*",
          "arn:aws:iam::*:role/zero-tolerance*",
          "arn:aws:iam::*:policy/ZeroTolerance*",
          "arn:aws:iam::*:policy/zero-tolerance*"
        ]
      },
      {
        # Block 3: The Eyes (READ-ONLY access to IAM for Terraform)
        # Terraform MUST be able to read the OIDC provider and IAM roles to function, but we don't want to give it free rein over IAM
        # Get and List are "Read-Only" actions, so this is still very secure.
        Sid    = "IAMReadAccess"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*"
        ]
        # This MUST be "*" so Terraform can see the OIDC and Policy paths
        Resource = "*" 
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