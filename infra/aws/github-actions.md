# AWS Deploy With GitHub Actions

This workspace deploys as two services:

- `ineeddownpipe-back`: Docker image -> ECR -> ECS service
- `ineeddownpipe-front`: Vite static build -> S3 -> CloudFront

The workflows live in:

- `.github/workflows/deploy-backend.yml`
- `.github/workflows/deploy-frontend.yml`

## 1. AWS Resources

Create these resources first:

### Backend

- ECR repository, for example `ineeddownpipe-api`
- ECS cluster
- ECS service running a task definition with one container
- Application Load Balancer or another public entrypoint for the API
- Task env:
  - `NODE_ENV=production`
  - `PORT=3001`
  - `CORS_ORIGIN=https://your-frontend-domain.com`
  - optional: `REFRESH_SECRET=...`

The container name in the ECS task definition must match GitHub variable `ECS_CONTAINER_NAME`.

### Frontend

- S3 bucket for the static site
- CloudFront distribution in front of the bucket
- CloudFront behavior should route all SPA paths to `/index.html` on 403/404

## 2. GitHub Repository Secret

Use GitHub OIDC, not long-lived AWS keys.

Create one GitHub Actions IAM role in AWS and add its ARN as a repository secret:

```text
AWS_ROLE_TO_ASSUME=arn:aws:iam::<account-id>:role/<role-name>
```

If this parent repository keeps `ineeddownpipe-back` and `ineeddownpipe-front` as private submodules, also create a fine-grained GitHub token with read-only `Contents` access to both submodule repositories and add it as:

```text
GH_SUBMODULE_TOKEN=github_pat_...
```

Without this token, `actions/checkout` can fail with `Repository not found` while cloning submodules, even when the repositories exist and you can access them locally.

The role trust policy should allow your GitHub repository to assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<github-org-or-user>/<repo-name>:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

## 3. GitHub Repository Variables

Set these under GitHub repo `Settings -> Secrets and variables -> Actions -> Variables`.

### Shared

```text
AWS_REGION=us-east-1
```

### Backend workflow

```text
ECR_REPOSITORY=ineeddownpipe-api
ECS_CLUSTER=your-ecs-cluster-name
ECS_SERVICE=your-ecs-service-name
ECS_CONTAINER_NAME=ineeddownpipe-api
```

### Frontend workflow

```text
FRONTEND_S3_BUCKET=your-static-site-bucket
CLOUDFRONT_DISTRIBUTION_ID=E1234567890ABC
VITE_API_URL=https://api.your-domain.com
VITE_SITE_URL=https://www.your-domain.com
```

`CLOUDFRONT_DISTRIBUTION_ID` can be empty if you do not want invalidations.

## 4. IAM Permissions

Attach permissions like these to the GitHub Actions role. Scope resources down to your account, bucket, repository, cluster, and service before production.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ],
      "Resource": "arn:aws:ecr:<region>:<account-id>:repository/ineeddownpipe-api"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::<account-id>:role/<ecs-task-execution-role>",
        "arn:aws:iam::<account-id>:role/<ecs-task-role>"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::your-static-site-bucket",
        "arn:aws:s3:::your-static-site-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::<account-id>:distribution/E1234567890ABC"
    }
  ]
}
```

## 5. Deploy

Push to `main`.

- Changes under `ineeddownpipe-back/**` deploy the backend.
- Changes under `ineeddownpipe-front/**` deploy the frontend.
- You can also run each workflow manually from GitHub Actions with `workflow_dispatch`.

