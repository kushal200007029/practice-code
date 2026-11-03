variable "region" { default = "ap-south-1" }
variable "project" { default = "practice-code" }
variable "cluster_version" { default = "1.30" }
variable "gitops_repo_url" { description = "HTTPS URL of the repository Argo CD should watch" }
variable "gitops_revision" { default = "main" }
variable "github_repository" { description = "Repository in OWNER/REPOSITORY form, permitted to deploy through GitHub Actions" }
variable "ansible_instance_type" { default = "t3.small" }
