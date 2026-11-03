output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.region }
output "api_ecr_repository" { value = aws_ecr_repository.api.repository_url }
output "web_ecr_repository" { value = aws_ecr_repository.web.repository_url }
output "ansible_instance_id" { value = aws_instance.ansible.id }
output "ansible_connect" { value = "aws ssm start-session --target ${aws_instance.ansible.id} --region ${var.region}" }
output "argocd_initial_password_command" { value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" }
output "github_actions_role_arn" { value = aws_iam_role.github_actions.arn }
