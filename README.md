# AWS VPC Peering Project (Terraform + GitHub Actions)

## Architecture
- **VPC A** `28.0.0.0/16`
  - Public subnet `28.0.1.0/24` + EC2, route table -> Internet Gateway
  - Private subnet `28.0.2.0/24` + EC2, route table -> peering
- **VPC B** `28.200.0.0/16`
  - Private subnet `28.200.1.0/24` + EC2, route table -> peering
- **VPC Peering** between A and B
- **Client C** reaches the public EC2 through the Internet Gateway

## Quick start (automated)
```bash
aws configure            # once, with an admin user
gh auth login            # once
bash scripts/setup.sh    # bucket, key pair, OIDC role, secrets, push -> deploys
```
After the workflow turns green: test (below). To remove everything run the
GitHub `destroy` workflow, then `bash scripts/teardown.sh`.

## Manual setup (alternative)
1. Create the state bucket:
   ```bash
   cd bootstrap
   terraform init
   terraform apply -var="bucket_name=<unique-bucket-name>"
   cd ..
   ```
2. In AWS IAM, add the OIDC provider `token.actions.githubusercontent.com`
   (audience `sts.amazonaws.com`) and a role trusted for
   `repo:<USER>/<REPO>:*` with EC2/VPC + S3 state-bucket permissions.
3. In GitHub -> Settings -> Secrets and variables -> Actions, add:

   | Secret | Value |
   |---|---|
   | `AWS_ROLE_ARN` | ARN of the role above |
   | `TF_STATE_BUCKET` | state bucket name |
   | `KEY_NAME` | existing EC2 key pair name |
   | `MY_IP` | your IP, e.g. `203.0.113.5/32` |

## Deploy
```bash
git init && git add . && git commit -m "AWS VPC peering project"
git branch -M main
git remote add origin https://github.com/<USER>/<REPO>.git
git push -u origin main
```
Open a PR to see the plan; merging to `main` applies it.

## Test
```bash
ssh -A -i key.pem ec2-user@<public_ec2_ip>
ping <private_a_ip>     # public -> private A
ping <private_b_ip>     # crosses the peering connection
```
Console check: VPC -> Peering connections = Active.

## Destroy
GitHub -> Actions -> Terraform -> Run workflow -> `destroy`.

## Notes
- `28.x.x.x` is public address space. Prefer `10.0.0.0/16` and `10.200.0.0/16` for real use.
- No NAT gateway, so private instances have no internet access (as in the diagram).
- Peering is non-transitive; client C can only reach VPC B via the public EC2.
