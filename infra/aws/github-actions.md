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

## 2. GitHub Repository Secrets

The workflows support the same OIDC variable name used by OrigemLab:

```text
AWS_ROLE_ARN=arn:aws:iam::<account-id>:role/<role-name>
```

Set `AWS_ROLE_ARN` under GitHub repository **Variables**.

If you prefer IAM user access keys instead, add these repository **Secrets**:

```text
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
```

If you are using temporary AWS credentials, also add:

```text
AWS_SESSION_TOKEN=...
```

The workflows validate that either `AWS_ROLE_ARN` is present, or both `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are present.

If this parent repository keeps `ineeddownpipe-back` and `ineeddownpipe-front` as private submodules, also create a fine-grained GitHub token with read-only `Contents` access to both submodule repositories and add it as:

```text
GH_SUBMODULE_TOKEN=github_pat_...
```

Without this token, `actions/checkout` can fail with `Repository not found` or `403` while cloning submodules, even when the repositories exist and you can access them locally.

## 3. GitHub Repository Variables

Set these under GitHub repo `Settings -> Secrets and variables -> Actions -> Variables`.

### Shared

```text
AWS_REGION=us-east-1
AWS_ROLE_ARN=arn:aws:iam::<account-id>:role/<role-name>
```

### Backend workflow

```text
ECR_REPOSITORY=ineeddownpipe-api
ECS_CLUSTER=your-ecs-cluster-name
ECS_SERVICE=your-ecs-service-name
ECS_DESIRED_COUNT=1
ECS_CONTAINER_PORT=3001
BACKEND_SUBMODULE_REF=main
```

The backend can scrape the product catalog at runtime. In production, it defaults to `AUTO_REFRESH_ON_STARTUP=if-empty`, so a fresh ECS task starts quickly for health checks and then fills `/app/data/products.json` in the background when no cached catalog exists.

Optional backend environment variables:

```text
AUTO_REFRESH_ON_STARTUP=if-empty
AUTO_REFRESH_STARTUP_DELAY_MS=1500
AUTO_REFRESH_INTERVAL_HOURS=0
REFRESH_MIN_HOURS=6
REFRESH_SECRET=your-refresh-secret
```

Set `REFRESH_SECRET` as a GitHub secret. The backend workflow injects it into the ECS task definition so authenticated `POST /api/refresh` requests work in production.

### Used listings (Supabase + Stripe)

Backend **secrets** (Settings → Secrets and variables → Actions → Secrets):

```text
SUPABASE_SERVICE_ROLE_KEY=eyJ...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

Backend **variables**:

```text
SUPABASE_URL=https://txbmkfhjknqktiljpvkg.supabase.co
SITE_URL=https://www.your-domain.com
USED_LISTING_FEE_CENTS=1999
```

`SITE_URL` must match the public frontend URL (Stripe Checkout success/cancel redirects).

Frontend **variables** (same Supabase project):

```text
SUPABASE_URL=https://txbmkfhjknqktiljpvkg.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_...
```

The frontend workflow maps `SUPABASE_URL` → `VITE_SUPABASE_URL` at build time. The anon/publishable key is public in the browser bundle; keep the service role key backend-only.

For local Stripe webhooks: `stripe listen --forward-to localhost:3003/api/stripe/webhook` and paste the printed `whsec_...` into `STRIPE_WEBHOOK_SECRET`.

Set the other refresh values as GitHub repository variables if you want to override the defaults. `AUTO_REFRESH_ON_STARTUP=always` scrapes after every task start, and `false` disables startup scraping. Set `AUTO_REFRESH_INTERVAL_HOURS` to a positive number if you want the running service to refresh periodically. Without persistent storage, `/app/data` is ephemeral and the service will scrape again when ECS replaces the task.

`BACKEND_SUBMODULE_REF` controls which branch/ref is fetched from `ineeddownpipe-back` before building the Docker image. This avoids deploying an old submodule pointer from the parent repository.

`ECS_CONTAINER_NAME` is optional when the ECS task definition has only one container. Set it only if the task definition has multiple containers:

```text
ECS_CONTAINER_NAME=ineeddownpipe-api
```

The backend workflow creates/reuses an internet-facing Application Load Balancer and prints its public URL in the workflow summary. By default it infers VPC, subnets, and service security group from the ECS service network configuration. If inference is not enough, set:

```text
ECS_ALB_NAME=ineeddownpipe-back-alb
ECS_TARGET_GROUP_NAME=ineeddownpipe-back-tg
ECS_ALB_SUBNET_IDS=subnet-aaa subnet-bbb
ECS_VPC_ID=vpc-...
ECS_ALB_SECURITY_GROUP_ID=sg-...
```

Use public subnets for `ECS_ALB_SUBNET_IDS`.

If ECS reports `Target is in an Availability Zone that is not enabled for the load balancer`, the ALB does not include the AZ where the task was placed. Set `ECS_ALB_SUBNET_IDS` to the public subnets you want the ALB and ECS tasks to use. The workflow uses the same subnet list for ECS tasks by default. Set `ECS_TASK_SUBNET_IDS` only if you need a different task subnet list.

The backend workflow also ensures the selected ECS container has a `portMappings` entry for `ECS_CONTAINER_PORT` and sets container environment variable `PORT` to the same value. This is required for ECS service load balancer attachment.

For ECS services using `awsvpc` network mode, the ALB target group must use target type `ip`. If `ECS_TARGET_GROUP_NAME` points to an existing target group with target type `instance` (common for Elastic Beanstalk), the workflow creates a dedicated `ip` target group instead.

After updating the ECS service, the workflow verifies that the active task definition and at least one running task use the exact ECR image pushed in the current run. If the service is still running an old/wrong image, the deploy fails and prints the expected image, active image, task definition, and running task images.

### Frontend workflow

```text
FRONTEND_S3_BUCKET=your-static-site-bucket
CLOUDFRONT_DISTRIBUTION_ID=E1234567890ABC
VITE_API_URL=https://api.your-domain.com
VITE_SITE_URL=https://www.your-domain.com
SUPABASE_URL=https://txbmkfhjknqktiljpvkg.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_...
```

`VITE_API_URL` must include the protocol (`http://` or `https://`). Without it, the built frontend requests `/api/...` from CloudFront and receives `index.html` instead of JSON.

`CLOUDFRONT_DISTRIBUTION_ID` is required. The frontend workflow creates a `/*` invalidation after every successful S3 sync so CloudFront serves the newest build and SPA routing settings.

Optional:

```text
FRONTEND_SUBMODULE_REF=main
```

If unset, the frontend workflow checks out `main` from `ineeddownpipe-front` after cloning submodules (same pattern as `BACKEND_SUBMODULE_REF`).

### Submodule deploy checklist

This parent repo uses git submodules. A push that only bumps `ineeddownpipe-front` or `ineeddownpipe-back` changes the **gitlink** path (for example `ineeddownpipe-front`), not files under `ineeddownpipe-front/**`. The workflows listen for both patterns so deploys actually run.

Correct release order:

1. Commit and push changes inside `ineeddownpipe-front` (or `ineeddownpipe-back`).
2. In the parent repo: `git add ineeddownpipe-front && git commit && git push`.
3. Confirm GitHub Actions ran **Deploy frontend** (green). Or run it manually: Actions → Deploy frontend → Run workflow.

If Actions is skipped, the site stays on the old build even though you pushed the parent repo.

If **Run workflow** fails on checkout, set `GH_SUBMODULE_TOKEN` (read access to the private submodule repos).

After a successful deploy, hard-refresh the site (Ctrl+Shift+R) or wait ~1–2 minutes for CloudFront invalidation.

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
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:ModifyListener"
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

