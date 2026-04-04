# Zero-Tolerance FinOps

> **Enterprise-grade AWS cost governance automation** | Real-time EC2 policy enforcement with zero manual intervention


## 🎯 The Problem

Large organizations running hundreds or thousands of EC2 instances face critical challenges:

**💸 Uncontrolled Costs**  
Developers launch expensive instance types (m5.xlarge, c5.2xlarge) for testing and forget to stop them, burning thousands of dollars monthly

**🏷️ Untagged Resources**  
40-60% of instances run without proper tags, making cost allocation impossible

**❌ No Accountability**  
FinOps teams can't identify who owns which instances or which cost center to charge

**📊 Manual Audits Fail**  
Weekly spreadsheet reviews are too slow - non-compliant instances run for days before detection

**💰 Million-Dollar Impact**  
For companies spending millions on AWS, even 5% waste equals tens of thousands lost per month

**Real Example:** A single m5.4xlarge instance left running for a month costs ~$560. Multiply that by 50 forgotten instances = **$28,000/month wasted**.

## ✅ Our Solution

This project solves the problem with **automated, real-time enforcement**:

**✅ Instant Compliance**  
Non-compliant instances are stopped within seconds of launch, not days later

**✅ Forced Tagging**  
All instances must have `env` and `CostCenter` tags - enabling accurate FinOps tracking

**✅ Cost Control**  
Non-production instances restricted to small types (t2/t3.micro/small only)

**✅ Zero Manual Work**  
Automated daily audits with email reports - no spreadsheets needed

**✅ Measurable Savings**  
Organizations save **$10,000-$50,000+ monthly** by eliminating waste

### How It Saves Money

• Prevents expensive dev/test instances from running (saves 70-80% on non-prod costs)  
• Forces tagging for accurate chargeback to cost centers  
• Stops forgotten instances automatically  
• Provides audit trail for compliance teams



## 🏗️ Technical Architecture

![Zero-Tolerance Architecture](docs/architecture.png)


### Core Components

**Lambda Function**  
Policy enforcement engine written in Python 3.12

**EventBridge Rules**  
Real-time triggers for EC2 launches + scheduled daily audits

**SNS Topic**  
Pub/Sub messaging for email notifications

**IAM Roles**  
Least-privilege security with OIDC + custom policies

**S3 Backend**  
Versioned Terraform state with native lockfile (no DynamoDB required)

**GitHub Actions**  
CI/CD pipeline with OIDC authentication

---

## 🚀 What I Built

### 1. Serverless Policy Enforcement Engine

• Designed event-driven Lambda function with dual-mode operation  
• **Bouncer Mode**: Instant enforcement on new EC2 launches  
• **Auditor Mode**: Scheduled daily compliance scans  
• Implemented two-strike warning system for existing resources  
• Built centralized policy evaluation logic for maintainability

### 2. Infrastructure as Code (Terraform)

• Modularized Terraform configuration across 8 files for separation of concerns  
• Implemented S3 remote state with versioning, encryption, and native lockfile  
• Created least-privilege IAM policies (replaced admin access)  
• Built OIDC authentication for passwordless GitHub Actions

### 3. Enterprise CI/CD Pipeline

• **3-stage pipeline** with quality gates  
• 🧹 **Stage 1**: Format validation, syntax checks, linting (tflint)  
• 🔒 **Stage 2**: Security scanning (tfsec + Checkov)  
• 🚀 **Stage 3**: Terraform plan/apply with OIDC  
• Automated PR comments with Terraform plan previews  
• Branch protection with required status checks

### 4. Git Branching Strategy

• **Protected `main` branch** with enforcement rules  
• ✅ All CI checks must pass before merge  
• ✅ Pull request required (no direct commits)  
• ✅ Automated Terraform plan review  
• **Feature branch workflow**: `feature/* → PR → main`  
• **Automated deployments**: Only `main` branch triggers `terraform apply`

### 5. Security & Compliance

• Implemented AWS OIDC for zero-credential deployments  
• Scoped IAM policies to `ZeroTolerance*` namespace  
• Enabled S3 state encryption and versioning  
• Integrated security scanners in CI pipeline  
• Sensitive variables marked and stored in GitHub Secrets

---

## 📋 Policy Rules

**Production Protection**  
✅ Instances tagged `env=prod` are always ignored

**Instance Type Restriction**  
❌ Non-prod instances must use t2/t3.micro or t2/t3.small only

**Required Tags**  
❌ All instances must have `env` and `CostCenter` tags

**Two-Strike System**  
⚠️ Existing instances get warning → 🛑 Then stopped if not fixed

---

## ⚡ Quick Start

### Prerequisites

✅ AWS Account with admin access (only for initial setup)  
✅ GitHub repository  
✅ Terraform >= 1.11.0  
✅ AWS CLI configured  
✅ Email address for alerts

### Step 1: Initial Infrastructure Setup (Local)

**Note:** Admin permissions are required ONLY for the first deployment to create the OIDC provider and IAM roles. After that, the GitHub Actions pipeline uses least-privilege OIDC authentication with no stored credentials.

```bash
# Clone repository
git clone https://github.com/Nikhil-9391/zero-tolerance-finops.git
cd zero-tolerance-finops

# Set required variables
export TF_VAR_security_alert_email="your-email@example.com"
export TF_VAR_is_enabled=true

# Deploy OIDC infrastructure first (requires admin access)
cd terraform
terraform init
terraform plan -target=aws_iam_openid_connect_provider.github \
               -target=aws_iam_role.github_actions_role \
               -target=aws_iam_policy.github_actions_least_privilege \
               -target=aws_iam_role_policy_attachment.github_actions_custom_attach

terraform apply -target=aws_iam_openid_connect_provider.github \
                -target=aws_iam_role.github_actions_role \
                -target=aws_iam_policy.github_actions_least_privilege \
                -target=aws_iam_role_policy_attachment.github_actions_custom_attach

# Copy the OIDC role ARN from output - you'll need this for GitHub
```

**Important:** After this step, you no longer need admin access. All future deployments will use GitHub Actions with the least-privilege OIDC role.

### Step 2: Configure GitHub for CI/CD

**Add Repository Variables:**

Go to: `Settings → Secrets and variables → Actions → Variables`

• `AWS_OIDC_ROLE_ARN`: Copy from Terraform output

**Add Repository Secrets:**

Go to: `Settings → Secrets and variables → Actions → Secrets`

• `SECURITY_ALERT_EMAIL`: Your notification email

### Step 3: Protect Main Branch

Go to: `Settings → Branches → Add branch protection rule`

**Configure:**

• Branch name pattern: `main`  
• ✅ Require a pull request before merging  
• ✅ Require status checks to pass before merging  
• Select: `quality-gates`, `security-scans`  
• ✅ Require branches to be up to date before merging

### Step 4: Confirm SNS Subscription

Check your email and click the confirmation link to receive alerts.

### Step 5: Test the System

Push to `main` to trigger automated deployment:

```bash
git add .
git commit -m "Enable FinOps automation"
git push origin main
```

**What happens next:**

✅ GitHub Actions pipeline automatically runs  
✅ OIDC authenticates with AWS (no credentials needed)  
✅ Terraform deploys remaining infrastructure (Lambda, EventBridge, SNS)  
✅ System is live and monitoring EC2 instances

---

## 🧪 Testing Guide

### Test 1: Missing Required Tags (Immediate Stop)

```bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-instance}]'
```

**Expected Result:**

⏱️ Instance stopped within 5-10 seconds  
📧 Email alert: "New Instance Stopped - Missing tags: ['env', 'CostCenter']"  
🏷️ Instance tagged: `SecurityStatus=Quarantined-Policy-Violation`

### Test 2: Expensive Non-Prod Instance (Immediate Stop)

```bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.medium \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=env,Value=dev},{Key=CostCenter,Value=Engineering}]'
```

**Expected Result:**

⏱️ Instance stopped within 5-10 seconds  
📧 Email alert: "Expensive non-prod type (t2.medium)"

### Test 3: Compliant Instance (Allowed)

```bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=env,Value=dev},{Key=CostCenter,Value=Engineering},{Key=Name,Value=compliant-test}]'
```

**Expected Result:**

✅ Instance runs normally  
📧 No alert sent

### Test 4: Production Instance (Protected)

```bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type m5.xlarge \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=env,Value=prod},{Key=CostCenter,Value=Production}]'
```

**Expected Result:**

✅ Instance runs normally (production is exempt)  
📧 No alert sent

### Test 5: Daily Audit Report

Wait for the next scheduled run (9 AM UTC) or manually invoke:

```bash
aws lambda invoke \
  --function-name zero-tolerance-remediation \
  --payload '{"detail-type":"Scheduled Event"}' \
  response.json
```

**Expected Result:**

📧 Email report with warned/stopped instances  
🏷️ Non-compliant instances tagged with `FinOpsWarning`

---

## 🔄 CI/CD Pipeline Details

### Pipeline Stages

```yaml
┌─────────────────────────────────────────────────────────────┐
│  Stage 1: Quality Gates (Format, Validate, Lint)            │
│  ├─ terraform fmt -check                                    │
│  ├─ terraform validate                                      │
│  └─ tflint                                                  │
└─────────────────────────────────────────────────────────────┘
                          ↓ (Pass)
┌─────────────────────────────────────────────────────────────┐
│  Stage 2: Security Scans (tfsec, Checkov)                   │
│  ├─ tfsec (Terraform security scanner)                      │
│  └─ Checkov (Policy-as-code validation)                     │
└─────────────────────────────────────────────────────────────┘
                          ↓ (Pass)
┌─────────────────────────────────────────────────────────────┐
│  Stage 3: Deploy (Plan on PR, Apply on main)                │
│  ├─ OIDC Authentication (passwordless)                      │
│  ├─ terraform plan (PR: post as comment)                    │
│  └─ terraform apply (main branch only)                      │
└─────────────────────────────────────────────────────────────┘
```

### Key Features

**Zero Credentials**  
OIDC authentication eliminates AWS access keys

**Automated PR Reviews**  
Terraform plans posted as PR comments

**Branch Protection**  
Only `main` branch triggers deployments

**Security First**  
Dual security scanners catch misconfigurations

**Fail Fast**  
Pipeline stops at first failure

---

## 🛡️ Security Features

**Kill Switch**  
Set `is_enabled = false` to disable all automation instantly

**Production Protection**  
Instances tagged `env=prod` are always ignored by the system

**Least Privilege IAM**  
Custom policies scoped to `ZeroTolerance*` namespace only

**OIDC Authentication**  
No AWS credentials stored in GitHub - passwordless deployments (admin access only needed for initial setup)

**State Encryption**  
S3 backend with encryption and versioning enabled

**Audit Trail**  
All actions logged to CloudWatch Logs for compliance

**Two-Strike System**  
Existing instances get warning before enforcement

---

## 💰 Cost Analysis

**Estimated Monthly Cost: < $5**

**Lambda**  
~1,000 invocations/month → $0.20 (free tier eligible)

**EventBridge**  
2 rules + ~30 events/month → $0.00 (free tier)

**SNS**  
~30 email notifications → $0.00 (free tier)

**S3**  
State file storage (~1 MB) with native lockfile → $0.02

**CloudWatch Logs**  
~10 MB/month → $0.01

---

**ROI Calculation:**  
Saves $10,000-$50,000+ monthly vs. costs < $5/month = **200,000%+ ROI**

---

## 📁 Project Structure

```
zero-tolerance-finops/
├── .github/
│   └── workflows/
│       └── deploy.yml              # 3-stage CI/CD pipeline
├── scripts/
│   └── tf-init.sh                  # S3 backend auto-bootstrap
├── src/
│   └── remediation.py              # Lambda enforcement engine
├── terraform/
│   ├── main.tf                     # Provider + default tags
│   ├── backend.tf                  # S3 remote state
│   ├── variables.tf                # Input variables
│   ├── outputs.tf                  # Output values
│   ├── lambda.tf                   # Lambda function + packaging
│   ├── eventbridge.tf              # Event rules (launch + cron)
│   ├── iam.tf                      # Lambda execution role
│   ├── sns.tf                      # Email notifications
│   └── oidc.tf                     # GitHub OIDC provider + role
├── .gitignore
├── LICENSE
└── README.md
```

---

## 🔧 Configuration

### Customize Policy Rules

Edit `src/remediation.py`:

```python
# Add/remove required tags
REQUIRED_TAGS = ['env', 'CostCenter', 'Owner']  

# Restrict allowed instance types
ALLOWED_DEV_TYPES = ['t2.micro', 't3.micro']  
```

### Change AWS Region

Edit `terraform/variables.tf`:

```hcl
variable "aws_region" {
  default = "us-east-1"  # Change to your region
}
```

### Adjust Audit Schedule

Edit `terraform/eventbridge.tf`:

```hcl
schedule_expression = "cron(0 9 * * ? *)"  # Daily at 9 AM UTC
```

---

## 🐛 Troubleshooting

### Lambda Not Triggering

```bash
# Check EventBridge rules
aws events list-rules --name-prefix zero-tolerance

# Verify Lambda permissions
aws lambda get-policy --function-name zero-tolerance-remediation
```

### Email Alerts Not Received

1. Check SNS subscription status:
   ```bash
   aws sns list-subscriptions-by-topic --topic-arn <YOUR_TOPIC_ARN>
   ```
2. Confirm email in inbox/spam folder
3. Resend confirmation:
   ```bash
   aws sns subscribe --topic-arn <ARN> --protocol email --notification-endpoint your@email.com
   ```

### Terraform State Locked

```bash
# The state uses S3 native lockfile (use_lockfile = true)
# If locked, wait for the operation to complete or force unlock
terraform force-unlock <LOCK_ID>
```

### CI/CD Pipeline Failing

1. Check GitHub Actions logs: `Actions` tab → Select failed workflow
2. Verify OIDC role ARN in repository variables
3. Confirm `SECURITY_ALERT_EMAIL` secret is set
4. Test OIDC authentication:
   ```bash
   aws sts get-caller-identity
   ```

---

## 🎓 Skills Demonstrated

### Cloud Engineering
☁️ AWS serverless architecture (Lambda, EventBridge, SNS)  
🏗️ Infrastructure as Code with Terraform  
🔐 IAM security with least-privilege policies  
📦 S3 backend with native lockfile (Terraform 1.11+)  
🔑 OIDC authentication for passwordless CI/CD

### DevOps & Automation
🚀 GitHub Actions CI/CD pipeline  
🔄 Git branching strategy with branch protection  
🧪 Automated testing and validation  
🔒 Security scanning (tfsec, Checkov)  
📊 Infrastructure monitoring and alerting

### Software Engineering
🐍 Python development for AWS Lambda  
📝 Clean code with separation of concerns  
🎯 Event-driven architecture design  
🧩 Modular and maintainable codebase  
📚 Comprehensive documentation

### FinOps & Cost Optimization
💰 Cost governance and policy enforcement  
🏷️ Resource tagging for cost allocation  
📈 Automated compliance auditing  
💡 Measurable ROI and cost savings

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

All PRs automatically run quality gates and security scans before merge.

---

## 📧 Contact

**Built by**: Nikhil  
**Email**   : [@mail](https://nareddulanikhil@gmail.com)
**GitHub**: [@Nikhil-9391](https://github.com/Nikhil-9391)  
**Project**: [zero-tolerance-finops](https://github.com/Nikhil-9391/zero-tolerance-finops)

---


**⭐ Star this repo if you find it useful!**

*Automated FinOps enforcement that saves thousands in AWS costs


