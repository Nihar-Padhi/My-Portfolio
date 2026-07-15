# Portfolio Deploy Guide — Free Path (S3 + CloudFront + GitHub Actions)

**Goal:** site live for **₹0** at the CloudFront endpoint `https://dxxxxxxxx.cloudfront.net`,
served from a **private** S3 bucket, with **push-to-`main` auto-deploy** via GitHub Actions.

**No custom domain. No ACM certificate. No DNS.** CloudFront gives free HTTPS on its own
`*.cloudfront.net` domain — that's the URL we use. A custom domain can be bolted on later
(Appendix A) with zero rebuild.

Replace `<...>` placeholders as you go. Fill the VALUES table at the bottom as you create things.

---

## Status so far
- [x] Phase 1 — S3 bucket `niharpadhi-site` created (private, ap-south-1)
- [ ] Phase 2 — CloudFront distribution (in progress)
- [ ] Phase 3 — bucket policy locked to CloudFront (OAC — likely auto-applied)
- [ ] Phase 4 — GitHub repo + OIDC auto-deploy

---

## Phase 0 — Prerequisites

- [ ] AWS account, console access to S3, CloudFront, IAM.
- [ ] GitHub account.
- [ ] (For the pipeline later) AWS CLI configured locally via `aws configure` — creds live in
      `~/.aws/credentials`, NEVER in the project folder or repo.
- [ ] **Security:** if any access-key CSV was saved to disk, delete it and rotate/deactivate
      that key in IAM. Long-lived keys never belong in a project folder.

---

## Phase 1 — Private S3 bucket  ✅ done

- Bucket: `niharpadhi-site`, region `ap-south-1`
- Block ALL public access: ON (CloudFront reaches it privately via OAC)
- Static website hosting: OFF (we use it as a private origin)
- [ ] Confirm `index.html` is uploaded to the bucket root:
```bash
aws s3 cp index.html s3://niharpadhi-site/index.html --region ap-south-1
```
(or drag it into the bucket in the console)

---

## Phase 2 — CloudFront distribution

Console → CloudFront → Create distribution:
- [ ] **Origin domain:** `niharpadhi-site.s3.ap-south-1.amazonaws.com` (the S3 REST endpoint, ✅)
- [ ] **Origin path:** **LEAVE BLANK.**  ← do NOT put `/index.html` here. Origin path is a
      prefix prepended to every request; setting it breaks routing. It must be empty (`-`).
- [ ] **Origin access:** Origin access control (OAC) → new OAC → use it. (Grant access = Yes ✅)
- [ ] **Viewer protocol policy:** Redirect HTTP to HTTPS ✅
- [ ] **Allowed methods:** GET, HEAD ✅
- [ ] **Cache policy:** CachingOptimized ✅
- [ ] **Custom SSL / Alternate domain names:** LEAVE DEFAULT / BLANK.
      (This is what keeps it free — we use the built-in CloudFront cert + `*.cloudfront.net`.)
- [ ] **General configuration → Default root object:** `index.html`  ← THIS is where index.html
      goes (not Origin path). Without it, the bare URL returns AccessDenied.
- [ ] Create. Note the **Distribution domain name** (`dxxxx.cloudfront.net`) and
      **Distribution ID** → VALUES table.
- [ ] Wait for status **Deployed** (~5–10 min).

> Common mix-up: **Origin path** (prefix on every request — leave blank) vs
> **Default root object** (file served for `/` — set to `index.html`). They are different fields.

---

## Phase 3 — Bucket policy locked to CloudFront (OAC)

Because OAC granted access, CloudFront usually **writes this bucket policy automatically.**
- [ ] Verify: S3 → `niharpadhi-site` → Permissions → Bucket policy. You should see a policy
      allowing `cloudfront.amazonaws.com` to `s3:GetObject`, scoped to your distribution.
- [ ] If it's empty, paste this (with your real account + distribution ID):

```json
{
  "Version": "2008-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipal",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::niharpadhi-site/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::<ACCOUNT_ID>:distribution/<DISTRIBUTION_ID>"
      }
    }
  }]
}
```

- [ ] **TEST:** open `https://<dxxxx>.cloudfront.net` — the site should load over HTTPS.
      **That is your live URL — you're shipped for ₹0.** Put it on résumé / LinkedIn.
      AccessDenied? → 90% it's the Default root object (Phase 2) or the bucket policy above.

---

## Phase 4 — GitHub repo + OIDC auto-deploy pipeline

### 4a. Push the code
- [ ] Create a GitHub repo (e.g. `portfolio-site`).
```bash
cd portfolio-site
git init
git add index.html DEPLOY-GUIDE.md
git commit -m "Initial portfolio site"
git branch -M main
git remote add origin https://github.com/<you>/portfolio-site.git
git push -u origin main
```
> `.github/workflows/deploy.yml` (below) also gets committed once you create it.

### 4b. OIDC — GitHub assumes an AWS role, NO stored keys

**Why:** each run gets short-lived creds by assuming an IAM role. No long-lived AWS keys in
GitHub. Safer, and the pattern worth learning (it's literally your résumé's "IAM least-privilege").

- [ ] IAM → Identity providers → Add provider:
  - Type: OpenID Connect
  - URL: `https://token.actions.githubusercontent.com`
  - Audience: `sts.amazonaws.com`

- [ ] IAM → Roles → Create role → Web identity → that provider, audience `sts.amazonaws.com`.
      Set its **trust policy** to lock it to YOUR repo + main branch:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:<you>/portfolio-site:ref:refs/heads/main" }
    }
  }]
}
```

- [ ] Attach a **least-privilege permissions policy** (only what deploy needs):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject","s3:DeleteObject","s3:ListBucket"],
      "Resource": ["arn:aws:s3:::niharpadhi-site","arn:aws:s3:::niharpadhi-site/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation"],
      "Resource": "arn:aws:cloudfront::<ACCOUNT_ID>:distribution/<DISTRIBUTION_ID>"
    }
  ]
}
```
- [ ] Note the role ARN → VALUES table.

### 4c. The workflow
- [ ] Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy site
on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
          aws-region: ap-south-1

      - name: Sync to S3
        run: aws s3 sync . s3://niharpadhi-site --delete --exclude ".git/*" --exclude ".github/*" --exclude "*.md"

      - name: Invalidate CloudFront cache
        run: aws cloudfront create-invalidation --distribution-id <DISTRIBUTION_ID> --paths "/*"
```

- [ ] Commit & push. Watch **GitHub → Actions**. From now on: **edit → push → live in ~30s.**

---

## Done (free version)

- [ ] `https://<dxxxx>.cloudfront.net` loads over HTTPS.
- [ ] Edit a word in `index.html`, push to `main`, Action ships it live.
- [ ] mailto:/LinkedIn links work on the LIVE site (blocked only in the artifact preview).

**Total cost: ₹0.** (S3 pennies + CloudFront free tier + free CloudFront HTTPS.)

---

## Appendix A — Add a custom domain LATER (optional, when you can spend on one)

Nothing rebuilds — you bolt a domain onto the CloudFront distribution you already have.
Buy from a cheap, honest-renewal registrar (Cloudflare Registrar at-cost, or Namecheap/Porkbun);
decline all upsells. Then:
1. **ACM cert (us-east-1 — required for CloudFront):** request a public cert for the domain,
   DNS-validate it via the registrar's DNS, wait for **Issued**.
2. **CloudFront:** edit distribution → add **Alternate domain names** → attach the ACM cert.
3. **Registrar DNS:** `www` → CNAME → `dxxxx.cloudfront.net`; apex → forward to `https://www.<domain>`.
4. Ping me with the registrar and I'll give exact DNS-menu steps.

---

## VALUES — fill in as you go

| Thing | Value |
|---|---|
| S3 bucket | `niharpadhi-site` |
| Bucket region | `ap-south-1` |
| AWS account ID | |
| CloudFront domain | `dxxxx.cloudfront.net` |
| CloudFront distribution ID | |
| GitHub repo | `<you>/portfolio-site` |
| IAM OIDC role ARN | |

## Common gotchas
- `/` returns AccessDenied → missing **Default root object = index.html** (Phase 2).
- Origin path set to `/index.html` → breaks routing; it must be **blank**.
- Bucket AccessDenied after OAC → bucket policy not applied / wrong distribution ID (Phase 3).
- Site not updating after push → CloudFront cache; the workflow invalidates, or run
  `aws cloudfront create-invalidation --distribution-id <ID> --paths "/*"` manually.
- OIDC "not authorized to assume role" → trust policy `sub` must match
  `repo:<you>/portfolio-site:ref:refs/heads/main` exactly.
