#Creating a code-commit repo
resource "aws_codecommit_repository" "my_frontend_repo" {
  repository_name = var.frontend-repo-name
  description     = "Repository for Project"

  tags = {
    Environment = "Dev"
    Name        = "code_commit_p2"
  }
}

#Creating a s3 bucket
resource "aws_s3_bucket" "myfrontendbucket" {
  bucket = var.frontend-bucket-name

}

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.myfrontendbucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

#Giving public access
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.myfrontendbucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

#Disabling acl controls
resource "aws_s3_bucket_acl" "example" {
  depends_on = [
    aws_s3_bucket_ownership_controls.example,
    aws_s3_bucket_public_access_block.example,
  ]

  bucket = aws_s3_bucket.myfrontendbucket.id
  acl    = "private"
}

# Bucket policy to allow public read access to objects
resource "aws_s3_bucket_policy" "mybucket_policy" {
  bucket = aws_s3_bucket.myfrontendbucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = [
				"s3:GetObject",
				"s3:PutObject"
			]
        Resource  = "${aws_s3_bucket.myfrontendbucket.arn}/*"
      }
    ]
  })
}

#Enabling static web hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.myfrontendbucket.id
  index_document {
    suffix = "index.html"
  }
}



# IAM role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-role-frontend-auto"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for CodeBuild role
resource "aws_iam_role_policy" "codebuild_role_policy" {
  name   = "codebuild-role-policy-frontend-auto"
  role   = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "sts:GetServiceBearerToken"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "codecommit:GitPull"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# CodeBuild project
resource "aws_codebuild_project" "codecommit_project" {
  name          = "codecommit-build-project-frontend-auto"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30  # 30 minutes build timeout

  source {
    type            = "CODECOMMIT"
    location        = "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/${var.frontend-repo-name}"
    git_clone_depth = 1

    buildspec = <<EOF
version: 0.2

phases:
  install:
    runtime-versions:
      nodejs: 18
    commands:
      - echo Installing the Angular CLI...
      - npm install -g @angular/cli
  pre_build:
    commands:
      - echo Installing dependencies...
      - npm install
  build:
    commands:
      - echo Building the Angular application...
      - ng build --configuration production
  post_build:
    commands:
      - echo Build completed successfully.
      - echo Copying files to S3...
      - aws s3 cp dist/revhire/ s3://${var.frontend-bucket-name}/ --recursive

artifacts:
  files:
    - '*/'
  base-directory: dist
  discard-paths: no
EOF
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true  # Needed for Docker commands
    image_pull_credentials_type = "CODEBUILD"
  }

  cache {
    type = "NO_CACHE"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/codecommit-build-project-frontend-auto"
      stream_name = "build-log"
    }
  }
}

# IAM Policy for CodePipeline to access CodeCommit
resource "aws_iam_policy" "codepipeline_codecommit_policy" {
  name        = "codepipeline-codecommit-policy-frontend-auto"
  description = "Policy to allow CodePipeline to access CodeCommit"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "codecommit:Get*",
          "codecommit:GitPull",
          "codecommit:List*",
          "codecommit:UploadArchive"
        ],
        Resource = "*"
      }
    ]
     })
}

# Attachment of IAM Policy to CodePipeline role
resource "aws_iam_policy_attachment" "codepipeline_codecommit_attachment" {
  name       = "codepipeline-codecommit-attachment-frontend-auto"
  roles      = [aws_iam_role.codepipeline_role.name]
  policy_arn = aws_iam_policy.codepipeline_codecommit_policy.arn
}
# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}


# IAM policy for CodePipeline role
resource "aws_iam_role_policy" "codepipeline_role_policy" {
  name   = "codepipeline-role-policy-frontend-auto"
  role   = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "codebuild:StartBuild",
          "codepipeline:PutJobSuccessResult",
          "codepipeline:PutJobFailureResult",
          "codebuild:BatchGetBuilds"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

# CodePipeline
resource "aws_codepipeline" "my_codepipeline" {
  name     = "rebhire-codepipeline-frontend-auto"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.myfrontendbucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = var.frontend-repo-name
        BranchName     = "master"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.codecommit_project.name
      }
    }
  }
}

# Define the IAM policy
resource "aws_iam_policy" "codebuild_batch_get_builds_policy" {
  name        = "codebuild_batch_get_builds_policy-frontend-auto"
  description = "Policy to allow BatchGetBuilds action on CodeBuild projects"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds"
      ],
      "Resource": "arn:aws:codebuild:us-east-1:654654292657:project/codecommit-build-project"
    }
  ]
}
EOF
}

# Attach the policy to the CodePipeline role
resource "aws_iam_role_policy_attachment" "attach_codebuild_policy_to_codepipeline_role" {
  role       = "codepipeline-role-frontend-auto"  # Replace with your actual CodePipeline role name
  policy_arn = aws_iam_policy.codebuild_batch_get_builds_policy.arn
}
# Define the IAM policy for CodePipeline role to allow BatchGetBuilds action
resource "aws_iam_policy" "codepipeline_codebuild_policy" {
  name        = "CodePipelineCodeBuildPolicy"
  description = "Policy to allow CodePipeline to call CodeBuild actions"
  policy      = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:BatchGetProjects"
        ],
        "Resource": "*"
      }
    ]
  })
}