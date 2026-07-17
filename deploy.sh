#!/bin/bash
# Manual deploy: sync the site to S3 and clear the CloudFront cache.
# Usage:  ./deploy.sh
# Requires: aws CLI configured with credentials that can write to the bucket
#           and create CloudFront invalidations (your Admin user works).

set -euo pipefail

BUCKET="niharpadhi-site"
DISTRIBUTION_ID="E2O3U6XU96WGKY"
AWS_PROFILE="${AWS_PROFILE:-personal-portfolio}"

echo "→ Syncing site to s3://$BUCKET with AWS profile '$AWS_PROFILE' ..."
aws s3 sync . "s3://$BUCKET" \
  --profile "$AWS_PROFILE" \
  --delete \
  --exclude ".git/*" \
  --exclude ".github/*" \
  --exclude "*.md" \
  --exclude "deploy.sh"

echo "→ Invalidating CloudFront cache ..."
aws cloudfront create-invalidation \
  --profile "$AWS_PROFILE" \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --query 'Invalidation.Id' --output text

echo "✓ Done. Live at https://d37defckk4zbws.cloudfront.net (allow ~1 min for cache clear)."
