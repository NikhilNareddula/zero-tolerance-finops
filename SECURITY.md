# Security Overview

## 🔒 Security Features

Zero-Tolerance FinOps implements enterprise-grade security practices to ensure safe, compliant cloud cost governance.

---

## Core Security Principles

### Least Privilege Access (Defense in Depth)

**Lambda Function IAM Policy**
-  `ec2:DescribeInstances` → Only read instance metadata (wildcard required for AWS API)
-  `ec2:StopInstances` + `ec2:CreateTags` → Limited to **current account & region**
-  `sns:Publish` → Limited to **specific SNS topic ARN only** (not all topics)
-  CloudWatch Logs → Write-only permissions
-  **NO** EC2 termination (only stop)
-  **NO** admin permissions
-  **NO** credential creation

**GitHub Actions IAM Policy**
-  OIDC-based temporary credentials (no stored secrets)
-  Terraform `init`, `plan`, `apply` permissions only
-  Limited to **specific repository** (`repo:OWNER/REPO:*`)
-  Policy scoped to ZeroTolerance resources only
-  **NO** IAM policy modification
-  **NO** user/role creation
-  **NO** access to other projects

**Production Protection**
- Instances tagged `env=prod` are **never** stopped
- Two-strike warning system for existing resources
- Kill switch (`is_enabled = false`) for instant disable
- Manual override requires explicit tag: `FinOpsException=Approved`

### Data Protection & Privacy

**Encryption in Transit**
-  HTTPS/TLS for all AWS API calls (boto3 enforces)
-  GitHub Actions → AWS via OIDC (no credentials transmitted)
-  SNS notifications encrypted (AWS-managed KMS)

**Encryption at Rest**
-  Terraform state encrypted in S3 (SSE-S3 by default, upgradeable to KMS)
-  S3 versioning enabled for state rollback
-  CloudWatch Logs encrypted (AWS-managed)

**Data Minimization**
-  No customer data stored (instance IDs & tags only)
-  No credential storage in Terraform or Lambda
-  No logs containing sensitive information
-  Sensitive variables marked in Terraform with `sensitive = true`

### Authentication & Authorization

**OIDC Passwordless Deployment** (No Stored Credentials)
```
GitHub Actions → GitHub OIDC Provider → AWS IAM → AssumeRole
└─ Temporary credentials (15 min expiry)
└─ No AWS access keys stored in GitHub
└─ Automatic credential rotation
```

**Why OIDC is Better Than Access Keys:**
| Feature | OIDC | Access Keys |
|---------|------|-------------|
| Credential Storage |  None |  GitHub Secrets |
| Key Rotation |  Automatic |  Manual |
| Compromise Risk |  Low (15 min) |  High (until rotated) |
| Scalability |  Easy |  Key management nightmare |

**IAM Security Controls**
```
├── Federated Identity Provider
│   └─ GitHub: token.actions.githubusercontent.com
├── Role Assumption Conditions
│   ├─ Audience: sts.amazonaws.com only
│   └─ Subject: repo:OWNER/REPO:* only
└── Policy Attachment
    └─ Minimal required permissions only
```

### Compliance & Audit

**Complete Audit Trail**
-  All Lambda actions logged to CloudWatch
-  Instance state changes tagged with `FinOpsStatus` and `SecurityStatus`
-  SNS emails document every enforcement action
-  Terraform state history (S3 versioning)
-  GitHub Actions run logs (GitHub Audit Log API available)

**Compliance Standards Alignment**
-  **SOC 2** - Encrypted state, audit logs, least privilege
-  **ISO 27001** - Access controls, encryption, incident response
-  **HIPAA** - Encryption in transit & at rest
-  **PCI-DSS** - No credential storage, OIDC authentication
-  **CIS AWS** - Least privilege IAM, CloudTrail alternatives

---

## 🚨 Security Considerations & Risk Mitigation

### Deployment Phase Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Initial OIDC setup requires admin | Medium | ✅ One-time setup; documented in README |
| S3 bucket creation requires admin | Medium | ✅ Terraform bootstrap script provided |
| AWS account compromise | Critical | ✅ OIDC limits blast radius to 15 min |

**Mitigation Strategy:**
1. Run initial OIDC setup from **secure workstation** (not CI/CD)
2. Store Terraform state bucket in **separate account** (optional but recommended)
3. Enable **CloudTrail** logging for all IAM actions
4. Implement **MFA on root account**

### Operational Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Lambda stop-spree hitting prod instances | Critical |  Prod instances hardcoded as exempt |
| Developer accidentally enables enforcement | Medium |  Kill switch requires explicit Terraform apply |
| Notification email exposed | Low | SNS encryption, email not logged |
| Instance tags accidentally deleted | Low | Lambda re-applies tags on next run |

**Safeguards Implemented:**
```hcl
# Kill Switch - explicit toggle required
is_enabled = var.is_enabled  # ← Requires explicit true to deploy

# Prod Hardcoded - no tags needed to protect
if env == 'prod':
    return 'IGNORE', 'Production instance'  # Immutable logic

# Two-Strike System - grace period for existing instances
Run 1: Add warning tag → Email notification
Run 2: Stop instance → Severe email notification
```

### Logging & Monitoring

**CloudWatch Integration**
```json
{
  "timestamp": "2026-04-24T10:30:00Z",
  "level": "WARNING",
  "message": "BOUNCER: Stopping i-123456",
  "instance_id": "i-123456",
  "action": "STOP",
  "reason": "Instance type t2.xlarge not allowed for dev environment"
}
```

**Log Analysis Commands**
```bash
# Find all enforcement actions in last 24 hours
aws logs filter-log-events \
  --log-group-name /aws/lambda/zero-tolerance-remediation \
  --filter-pattern '[timestamp, level="WARNING", ...]' \
  --start-time $(date -d '24 hours ago' +%s)000

# Track cost savings
aws logs filter-log-events \
  --filter-pattern '[message="*monthly*savings*"]'
```

---

## 📋 Pre-Deployment Security Checklist

**Before deploying to production, verify:**

- [ ] **AWS Account**
  - [ ] Root account uses MFA
  - [ ] CloudTrail enabled
  - [ ] VPC Flow Logs enabled (optional but recommended)
  - [ ] AWS Config enabled (optional)

- [ ] **GitHub Repository**
  - [ ] Requires code reviews (branch protection)
  - [ ] Commits signed (GPG)
  - [ ] No plaintext secrets in commit history (`git-secrets` configured)
  - [ ] Personal access tokens have minimum required scopes

- [ ] **Secrets Management**
  - [ ] `SECURITY_ALERT_EMAIL` configured in GitHub Actions secrets
  - [ ] `AWS_OIDC_ROLE_ARN` configured in GitHub Actions variables (not secrets)
  - [ ] No AWS keys stored anywhere

- [ ] **Terraform State**
  - [ ] S3 bucket has versioning enabled
  - [ ] S3 bucket has encryption enabled
  - [ ] S3 bucket has public access blocked
  - [ ] DynamoDB table for state locking configured

- [ ] **Testing**
  - [ ] All unit tests passing (pytest)
  - [ ] All linting checks passing (ruff, tflint)
  - [ ] Security scan passing (tfsec, Checkov)
  - [ ] Lambda function tested with mock events

- [ ] **Documentation**
  - [ ] README.md includes architecture diagram
  - [ ] SECURITY.md reviewed and understood
  - [ ] Runbooks documented for incident response
  - [ ] Break-glass procedures documented

---

## 🔍 Vulnerability Scanning & Response

### Automated Security Scanning in CI/CD

**tfsec** - Terraform security scanner
- Detects: Hard-coded credentials, unencrypted resources, overpermissive policies
- Run: `tfsec ./terraform`

**Checkov** - Policy-as-code framework
- Detects: CIS benchmarks, HIPAA, SOC 2, PCI-DSS compliance
- Run: `checkov -d ./terraform`

**ruff** - Python linter (includes security rules)
- Detects: Unsafe imports, insecure randomness, SQL injection patterns
- Run: `ruff check src/`

**GitHub Code Scanning** (Optional premium feature)
- Detects: Secrets, hardcoded credentials, dangerous patterns
- Requires: GitHub Advanced Security license

### Incident Response Plan

**If Lambda function is compromised:**
1. Set `is_enabled = false` in Terraform → Destroys all resources
2. Rotate GitHub OIDC thumbprints (oidc.tf)
3. Audit CloudWatch Logs for suspicious activity
4. Restore from S3 state versioning if needed

**If GitHub repository is compromised:**
1. Revoke OIDC trust via AWS console (immediate)
2. Rotate `SECURITY_ALERT_EMAIL` secret
3. Review GitHub Actions run logs
4. Re-validate all Terraform-deployed resources

**If AWS credentials are exposed:**
1. Not applicable - OIDC has no stored credentials
2. Compromise window: **15 minutes** (token expiration)
3. Automated credential rotation after Lambda execution

---

## 📚 Security Best Practices (FAQs)

**Q: Why not just use AWS Access Keys for CI/CD?**
A: Access keys are static, shareable secrets prone to accidental exposure. OIDC provides temporary credentials with automatic rotation—industry standard for 2025+.

**Q: What if I need to access AWS from my laptop?**
A: Use `aws sso` (AWS Single Sign-On) with MFA. Never use long-lived access keys on local machines.

**Q: Can I stop production instances?**
A: No—code explicitly exempts `env=prod`. Requires code modification + PR review to change.

**Q: What happens if my email is hacked?**
A: Attacker receives notifications only, can't modify AWS resources (no credentials in email).

**Q: Should I use KMS for Terraform state?**
A: For Fortune 500: Yes, use customer-managed KMS keys. For small teams: S3 default encryption sufficient.

---

## 📖 Related Security Documentation

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [GitHub Actions Security Hardening](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_github-oidc.html)
- [Terraform AWS Provider Security](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_role)
- [tfsec Documentation](https://aquasecurity.github.io/tfsec/)
- [Checkov Policy Reference](https://www.checkov.io/docs/intro)

---


