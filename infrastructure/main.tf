provider "aws" { region = var.region }

data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

locals {
  name         = "${var.project}-eks"
  tags         = { Project = var.project, ManagedBy = "Terraform" }
  github_owner = split("/", var.github_repository)[0]
  github_repo  = split("/", var.github_repository)[1]
}

module "eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "20.31.6"
  cluster_name                             = local.name
  cluster_version                          = var.cluster_version
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  cluster_addons = {
    coredns              = {}
    "kube-proxy"         = {}
    "vpc-cni"            = {}
    "aws-ebs-csi-driver" = {}
  }
  vpc_id     = data.aws_vpc.default.id
  subnet_ids = slice(data.aws_subnets.default.ids, 0, 3)
  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      iam_role_additional_policies = {
        ebs_csi = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }
  tags = local.tags
}

resource "aws_ecr_repository" "api" {
  name = "${var.project}/api"
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}
resource "aws_ecr_repository" "web" {
  name = "${var.project}/web"
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

resource "random_password" "mongodb" {
  length  = 32
  special = false
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
resource "aws_iam_role" "github_actions" {
  name               = "${var.project}-github-actions"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = aws_iam_openid_connect_provider.github.arn }, Condition = { StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }, StringLike = { "token.actions.githubusercontent.com:sub" = "repo:${local.github_owner}@*/${local.github_repo}@*:ref:refs/heads/main" } } }] })
  tags               = local.tags
}
resource "aws_iam_role_policy" "github_ecr" {
  name   = "ecr-publish"
  role   = aws_iam_role.github_actions.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" }, { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"], Resource = [aws_ecr_repository.api.arn, aws_ecr_repository.web.arn] }] })
}

resource "aws_iam_role" "ansible" {
  name               = "${var.project}-ansible-control"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = local.tags
}
resource "aws_iam_role_policy_attachment" "ansible_ssm" {
  role       = aws_iam_role.ansible.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ansible" {
  name = "${var.project}-ansible-control"
  role = aws_iam_role.ansible.name
}
resource "aws_security_group" "ansible" {
  name        = "${var.project}-ansible-control"
  description = "No inbound access; manage via SSM"
  vpc_id      = data.aws_vpc.default.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}
resource "aws_instance" "ansible" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.ansible_instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ansible.id]
  iam_instance_profile   = aws_iam_instance_profile.ansible.name
  user_data              = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y ansible awscli unzip
  EOF
  tags                   = merge(local.tags, { Name = "${var.project}-ansible-control" })
}

data "aws_eks_cluster_auth" "this" { name = module.eks.cluster_name }
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.12"
  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }
  depends_on = [module.eks]
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }
  depends_on = [module.eks]
}

resource "helm_release" "mongodb" {
  name             = "mongodb"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "mongodb"
  namespace        = "todo"
  create_namespace = true
  version          = "20.0.16"
  set {
    name  = "architecture"
    value = "standalone"
  }
  set {
    name  = "auth.usernames[0]"
    value = "todo"
  }
  set {
    name  = "auth.databases[0]"
    value = "todo"
  }
  set_sensitive {
    name  = "auth.passwords[0]"
    value = random_password.mongodb.result
  }
  set {
    name  = "persistence.size"
    value = "8Gi"
  }
  depends_on = [kubernetes_storage_class_v1.gp3]
}
