#!/usr/bin/env bash
# Run AFTER the GitHub "destroy" workflow has finished successfully.
# Removes the state bucket, IAM role and key pair created by setup.sh.
set -uo pipefail

REGION="ap-south-1"
KEY_NAME="vpc-project-key"
ROLE_NAME="github-terraform-role"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="tfstate-${ACCOUNT_ID}-vpc-peering"

read -rp "Delete bucket $BUCKET, role $ROLE_NAME and key $KEY_NAME? (yes/no) " ans
[ "$ans" = "yes" ] || exit 0

echo "==> Emptying bucket"
aws s3api list-object-versions --bucket "$BUCKET" --query 'Versions[].[Key,VersionId]' --output text 2>/dev/null |
while read -r k v; do
  [ -n "$k" ] && [ "$k" != "None" ] && aws s3api delete-object --bucket "$BUCKET" --key "$k" --version-id "$v" >/dev/null
done
aws s3api list-object-versions --bucket "$BUCKET" --query 'DeleteMarkers[].[Key,VersionId]' --output text 2>/dev/null |
while read -r k v; do
  [ -n "$k" ] && [ "$k" != "None" ] && aws s3api delete-object --bucket "$BUCKET" --key "$k" --version-id "$v" >/dev/null
done
aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"

echo "==> Removing IAM role"
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name tf-state-and-ssm
aws iam delete-role --role-name "$ROLE_NAME"

echo "==> Removing key pair"
aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
rm -f "${KEY_NAME}.pem"
echo "Cleanup complete."
