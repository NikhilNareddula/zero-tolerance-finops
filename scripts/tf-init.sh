#!/bin/bash
set -e

# 1. AUTO-DETECT: Get your Account ID and current AWS region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# If no region is set in your environment, default to Mumbai
REGION=$(aws configure get region)
REGION=${REGION:-"ap-south-1"}

# 2. DEFINE: The unique bucket name using your Account ID
BUCKET_NAME="zero-tolerance-state-${ACCOUNT_ID}"

echo "-----------------------------------------------"
echo "🚀 Target Region: $REGION"
echo "📦 Target Bucket: $BUCKET_NAME"
echo "-----------------------------------------------"

# 3. BOOTSTRAP: Create the bucket if it doesn't exist
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "✅ Bucket exists."
else
    echo "⚠️  Creating bucket $BUCKET_NAME..."
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
    
    # Enable versioning so you have a "Time Machine" for your state
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
fi

# 4. INITIALIZE: Tell Terraform to use these settings
terraform init \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="key=zero-tolerance/terraform.tfstate" \
  -backend-config="region=${REGION}" \
  -reconfigure
