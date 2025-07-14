terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}


provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Local values
locals {
  cluster_name = "${var.project_name}-cluster"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# VPC Module
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }

  tags = local.common_tags
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Use shorter names and disable name prefixes to avoid length issues
  iam_role_name            = "${var.project_name}-cluster-role"
  iam_role_use_name_prefix = false

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    main = {
      name           = "${var.project_name}-workers"
      instance_types = ["t3.medium"]
      
      min_size     = 1
      max_size     = 3
      desired_size = 2

      # Use shorter names and disable name prefixes
      iam_role_name            = "${var.project_name}-node-role"
      iam_role_use_name_prefix = false

      labels = {
        Environment = var.environment
        NodeGroup   = "main"
      }

      tags = local.common_tags
    }
  }

  # Cluster access entry
  access_entries = {
    admin = {
      kubernetes_groups = []
      principal_arn     = data.aws_caller_identity.current.arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = local.common_tags
}

# S3 Bucket for document storage
resource "aws_s3_bucket" "documents" {
  bucket = "${var.project_name}-documents"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "documents" {
  bucket = aws_s3_bucket.documents.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for results
resource "aws_dynamodb_table" "results" {
  name           = "${var.project_name}-results"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name     = "status-index"
    hash_key = "status"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true
  }

  tags = local.common_tags
}

# ECR Repository
resource "aws_ecr_repository" "document_processor" {
  name                 = "${var.project_name}/document-processor"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "document_processor" {
  repository = aws_ecr_repository.document_processor.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# IAM role for the document processor pods
resource "aws_iam_role" "document_processor" {
  name = "${var.project_name}-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:default:document-processor-sa"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for document processor
resource "aws_iam_policy" "document_processor" {
  name = "${var.project_name}-pod-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.documents.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.results.arn,
          "${aws_dynamodb_table.results.arn}/index/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "document_processor" {
  role       = aws_iam_role.document_processor.name
  policy_arn = aws_iam_policy.document_processor.arn
}

# AWS Load Balancer Controller IAM role
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${var.project_name}-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Download and attach AWS Load Balancer Controller policy
data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name   = "${var.project_name}-alb-controller-policy"
  policy = data.http.alb_controller_policy.response_body
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}