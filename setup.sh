#!/usr/bin/env bash
# One-time setup: state bucket, key pair, GitHub OIDC role, GitHub secrets, push.
# Requires: aws CLI (configured), git, curl, and GitHub CLI `gh` (logged in: gh auth login).
# On Windows run this in Git Bash.
set -euo pipefail

REGION="ap-south-1"
KEY_NAME="vpc-project-key"
ROLE_NAME="github-terraform-role"

read -rp "GitHub username: " GH_USER
read -rp "GitHub repo name [aws-vpc-peering]: " GH_REPO
GH_REPO="${GH_REPO:-aws-vpc-peering}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="tfstate-${ACCOUNT_ID}-vpc-peering"
MY_IP="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')/32"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

echo "==> Account: $ACCOUNT_ID | Bucket: $BUCKET | Your IP: $MY_IP"

# 1. State bucket
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "==> Bucket exists"
else
  echo "==> Creating state bucket"
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 2. EC2 key pair
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "==> Key pair exists"
else
  echo "==> Creating key pair (saved as ${KEY_NAME}.pem)"
  aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" \
    --query KeyMaterial --output text > "${KEY_NAME}.pem"
  chmod 400 "${KEY_NAME}.pem" || true
fi

# 3. GitHub OIDC provider
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "==> OIDC provider exists"
else
  echo "==> Creating OIDC provider"
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
fi

# 4. IAM role
TMP="$(mktemp -d)"
cat > "$TMP/trust.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "${OIDC_ARN}" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:${GH_USER}/${GH_REPO}:*" }
    }
  }]
}
JSON
cat > "$TMP/inline.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "s3:ListBucket", "Resource": "arn:aws:s3:::${BUCKET}" },
    { "Effect": "Allow", "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject"], "Resource": "arn:aws:s3:::${BUCKET}/*" },
    { "Effect": "Allow", "Action": "ssm:GetParameter", "Resource": "*" }
  ]
}
JSON

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "==> Updating role trust policy"
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "file://$TMP/trust.json"
else
  echo "==> Creating role"
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$TMP/trust.json" >/dev/null
fi
aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name tf-state-and-ssm \
  --policy-document "file://$TMP/inline.json"
ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)"

# 5. GitHub repo + secrets + push
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if ! gh repo view "${GH_USER}/${GH_REPO}" >/dev/null 2>&1; then
    echo "==> Creating GitHub repo"
    gh repo create "${GH_USER}/${GH_REPO}" --private
  fi
  echo "==> Setting GitHub secrets"
  gh secret set AWS_ROLE_ARN     --repo "${GH_USER}/${GH_REPO}" --body "$ROLE_ARN"
  gh secret set TF_STATE_BUCKET  --repo "${GH_USER}/${GH_REPO}" --body "$BUCKET"
  gh secret set KEY_NAME         --repo "${GH_USER}/${GH_REPO}" --body "$KEY_NAME"
  gh secret set MY_IP            --repo "${GH_USER}/${GH_REPO}" --body "$MY_IP"

  [ -d .git ] || git init -q
  git add .
  git commit -qm "AWS VPC peering project" || true
  git branch -M main
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/${GH_USER}/${GH_REPO}.git"
  echo "==> Pushing (this triggers the deployment)"
  git push -u origin main
  echo "Done. Watch progress: https://github.com/${GH_USER}/${GH_REPO}/actions"
else
  echo
  echo "gh CLI not available/logged in. Add these secrets manually in GitHub"
  echo "(Settings > Secrets and variables > Actions), then push the code:"
  echo "  AWS_ROLE_ARN    = $ROLE_ARN"
  echo "  TF_STATE_BUCKET = $BUCKET"
  echo "  KEY_NAME        = $KEY_NAME"
  echo "  MY_IP           = $MY_IP"
fi
