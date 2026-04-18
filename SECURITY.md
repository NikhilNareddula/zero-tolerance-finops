# Security Overview

## 🔒 Security Features

Zero-Tolerance FinOps implements enterprise-grade security practices to ensure safe, compliant cloud cost governance.

### Core Security Principles

**Least Privilege Access**
- Custom IAM policies scoped to `ZeroTolerance*` namespace only
- No admin permissions required after initial setup
- OIDC authentication eliminates stored credentials

**Production Protection**
- Instances tagged `env=prod` are never stopped
- Two-strike warning system for existing resources
- Kill switch (`is_enabled = false`) for instant disable

**Data Protection**
- S3 backend with encryption and versioning
- CloudWatch Logs for complete audit trail
- No sensitive data stored in code

### Authentication & Authorization

**OIDC Passwordless Deployment**
- GitHub Actions authenticates via OIDC federation
- No AWS access keys stored in CI/CD pipelines
- Follows AWS security best practices

**IAM Security**
- Custom policies with minimal required permissions
- Role-based access control
- Automated policy validation in CI/CD

### Compliance & Audit

**Audit Trail**
- All actions logged to CloudWatch Logs
- Instance tagging for compliance tracking
- Email notifications for all enforcement actions

**Security Scanning**
- tfsec integration for infrastructure security
- Checkov policy validation
- Automated security checks in CI/CD pipeline

## 🚨 Security Considerations

### Deployment Security
- Admin access required only for initial OIDC setup
- Least-privilege roles for ongoing operations
- Encrypted Terraform state management

### Operational Security
- Production instances protected from enforcement
- Warning system prevents accidental outages
- Manual override capabilities

### Data Security
- No customer data processed or stored
- AWS-native encryption for all resources
- Secure email notifications via SNS

## 📋 Security Checklist

- [x] OIDC authentication (no stored credentials)
- [x] Least privilege IAM policies
- [x] Production environment protection
- [x] Encrypted state storage
- [x] Audit logging enabled
- [x] Security scanning in CI/CD
- [x] Kill switch mechanism
- [x] Two-strike warning system

## 🔍 Vulnerability Reporting

If you discover a security vulnerability, please report it by:
1. Creating a GitHub issue with "SECURITY" label
2. Emailing security concerns to the project maintainer
3. Following responsible disclosure practices

## 📚 Related Security Documentation

- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [Terraform Security](https://www.terraform.io/docs/cloud/security.html)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)

---

*This security overview is maintained as part of the Zero-Tolerance FinOps project.*