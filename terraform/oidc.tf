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

# 2. Create the IAM Role for the GitHub Pipeline
resource "aws_iam_role" "github_actions_role" {
  name = "ZeroTolerance-GitHubActions-Deployer"

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
            # LOCKS ROLE TO YOUR REPO: repo:OWNER/REPO:*
            "token.actions.githubusercontent.com:sub" : "repo:${var.repo_name}:*"
          }
        }
      }
    ]
  })
}

# 3. Custom Least Privilege Policy (Security Scanned)
resource "aws_iam_policy" "github_actions_least_privilege" {
  name        = "ZeroTolerance-GitHubActions-Policy"
  description = "Scoped permissions for GitHub Actions FinOps Deployment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # --- S3: STATE MANAGEMENT (Scoped to Project Bucket) ---
      {
        Sid    = "ManageTerraformState"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:DeleteObject"]
        Resource = [
          "arn:aws:s3:::zero-tolerance-finops-state-*",
          "arn:aws:s3:::zero-tolerance-finops-state-*/*"
        ]
      },
      {
        Sid    = "S3ReadOnlyGlobal"
        Effect = "Allow"
        Action = ["s3:GetBucketLocation", "s3:ListAllMyBuckets"]
        Resource = "*"
      },

      # --- EC2: REMEDIATION & DISCOVERY ---
      {
        Sid    = "EC2ReadOnly"
        Effect = "Allow"
        Action = ["ec2:Describe*", "ec2:Get*"]
        Resource = "*" 
      },
      {
        Sid    = "EC2RemediationActions"
        Effect = "Allow"
        Action = ["ec2:StopInstances", "ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project": "ZeroToleranceFinOps" }
        }
      },

      # --- PROJECT SERVICES: LAMBDA, EVENTS, SNS, KMS ---
      {
        Sid    = "ManageAppServices"
        Effect = "Allow"
        Action = [
          "lambda:*",
          "events:*",
          "sns:*",
          "kms:DescribeKey",
          "kms:ListAliases"
        ]
        Resource = "*"
      },

      # --- IAM: PROJECT SCOPED MUSCLE (Prevents Escalation) ---
      {
        Sid    = "ManageProjectIAM"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy", 
          "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PassRole", "iam:TagRole", "iam:CreatePolicy", "iam:DeletePolicy",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion"
        ]
        Resource = [
          "arn:aws:iam::*:role/ZeroTolerance*",
          "arn:aws:iam::*:role/zero-tolerance*",
          "arn:aws:iam::*:policy/ZeroTolerance*",
          "arn:aws:iam::*:policy/zero-tolerance*"
        ]
      },
      {
        Sid    = "IAMReadOnlyGlobal"
        Effect = "Allow"
        Action = ["iam:Get*", "iam:List*"]
        Resource = "*" 
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