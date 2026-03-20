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

# 3. Give the Pipeline Role permission to build your infrastructure
# (Using Admin here for the initial bootstrap so it doesn't crash. 
#  scope this down to Least Privilege later).
# TODO: Restrict to least privilege policies after bootstrap is successful and stable.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_role.id
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 4. Output the Role ARN so we can easily copy it into your YAML file
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "The ARN of the IAM role to use in your GitHub Actions workflow for OIDC authentication."
}