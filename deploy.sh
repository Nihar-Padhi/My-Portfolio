#!/bin/bash
# Manual deploy: sync the site to S3 and clear the CloudFront cache.
# Usage:  ./deploy.sh
# Requires: aws CLI configured with credentials that can write to the bucket
#           and create CloudFront invalidations (your Admin user works).

set -euo pipefail

BUCKET="niharpadhi-site"
DISTRIBUTION_ID="E2O3U6XU96WGKY"

echo "→ Syncing site to s3://$BUCKET ..."
aws s3 sync . "s3://$BUCKET" \
  --delete \
  --exclude ".git/*" \
  --exclude "*.md" \
  --exclude "deploy.sh"

echo "→ Invalidating CloudFront cache ..."
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --query 'Invalidation.Id' --output text

echo "✓ Done. Live at https://d37defckk4zbws.cloudfront.net (allow ~1 min for cache clear)."
