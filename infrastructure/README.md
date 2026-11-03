# AWS infrastructure and GitOps

This folder deploys to Mumbai (`ap-south-1`) and uses the AWS account's default VPC and its default subnets. It creates an EKS cluster, ECR repositories, an SSM-only Ansible control host, in-cluster MongoDB, and Argo CD. It is a demo foundation; MongoDB runs as a single replica with EBS storage. Use a dedicated VPC and MongoDB Atlas or a managed/replicated MongoDB offering for production data.

## Deploy

Terraform, AWS CLI credentials with provisioning access, and `kubectl` are required. This takes roughly 15–25 minutes and incurs AWS charges (EKS, NAT Gateway, EC2, and storage).

```bash
cd infrastructure
copy terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: repository URL/name. Terraform generates the MongoDB password.
terraform init
terraform plan
terraform apply
aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)
```

The outputs include the Ansible SSM session command and Argo CD initial-password command. Get the Argo CD load-balancer hostname with `kubectl -n argocd get svc argocd-server`.

## GitHub Actions configuration

Set GitHub repository variables `AWS_REGION`, `ECR_API_REPOSITORY`, and `ECR_WEB_REPOSITORY` from Terraform outputs. Set the `AWS_GITHUB_ACTIONS_ROLE_ARN` repository secret to the `github_actions_role_arn` output. The role uses GitHub OIDC, so no long-lived AWS keys are stored in GitHub.

A push to `main` builds both images, pushes to ECR, and commits immutable image tags to `k8s/overlays/prod`. Argo CD watches that path and automatically applies it.

## Destroy

`terraform destroy` deletes this EKS environment and the demo database volume. Review the plan carefully first.
