# iNeedDownpipe (local workspace)

This folder groups **two separate GitHub repositories**, each deployable through GitHub Actions or AWS CodeBuild:

| Repo folder | GitHub (example) | AWS deploy |
|-------------|------------------|------------|
| [`ineeddownpipe-back/`](ineeddownpipe-back/) | `your-org/ineeddownpipe-back` | CodeBuild → ECR → ECS |
| [`ineeddownpipe-front/`](ineeddownpipe-front/) | `your-org/ineeddownpipe-front` | CodeBuild → S3 → CloudFront |

## Publish as two repos

```bash
# Backend
cd ineeddownpipe-back
git init
git add .
git commit -m "Initial API"
git remote add origin git@github.com:YOUR_ORG/ineeddownpipe-back.git
git push -u origin main

# Frontend
cd ../ineeddownpipe-front
git init
git add .
git commit -m "Initial frontend"
git remote add origin git@github.com:YOUR_ORG/ineeddownpipe-front.git
git push -u origin main
```

## Local dev (both together)

```bash
# Terminal 1 — API
cd ineeddownpipe-back && npm install && npm run dev

# Terminal 2 — UI (proxies /api when VITE_API_URL is unset)
cd ineeddownpipe-front && npm install && npm run dev
```

Or from the root (convenience only):

```bash
npm run install:all
npm run dev
```

## Wiring in production

1. Deploy **back** first; note the public URL (ALB / API Gateway).
2. Set front CodeBuild env `VITE_API_URL` to that URL.
3. Set back env `CORS_ORIGIN` to your CloudFront site URL.
4. Deploy **front**.

See each subfolder `README.md` for AWS details.

## GitHub Actions deploy

GitHub Actions workflows are available in `.github/workflows/`:

- `deploy-backend.yml`: builds `ineeddownpipe-back/Dockerfile`, pushes to ECR, registers a new ECS task definition revision, and updates the ECS service.
- `deploy-frontend.yml`: builds `ineeddownpipe-front`, syncs `dist/` to S3, and optionally invalidates CloudFront.

Setup guide: [`infra/aws/github-actions.md`](infra/aws/github-actions.md).

Because `ineeddownpipe-back` and `ineeddownpipe-front` are git submodules, private submodule repositories require the GitHub secret `GH_SUBMODULE_TOKEN` for Actions checkout.
