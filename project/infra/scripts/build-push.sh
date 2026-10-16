#!/usr/bin/env bash
set -euo pipefail
# Execute da raiz project: bash infra/scripts/build-push.sh lab-v1
infra_dir="$(cd "$(dirname "$0")/.." && pwd)"
project_dir="$(cd "$infra_dir/.." && pwd)"
tag="${1:?Uso: build-push.sh TAG_UNICA (ex. lab-v1)}"
[[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || { echo 'Tag inválida' >&2; exit 2; }
for cmd in aws docker terraform jq; do command -v "$cmd" >/dev/null || { echo "Falta $cmd" >&2; exit 1; }; done
region="$(terraform -chdir="$infra_dir" output -raw region)"
repos="$(terraform -chdir="$infra_dir" output -json ecr_repositories)"
registry="$(jq -r '.["service-a"] | split("/")[0]' <<<"$repos")"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
for module in service-a service-b worker; do
  repo="$(jq -r --arg module "$module" '.[$module]' <<<"$repos")"
  docker buildx build --platform linux/amd64 --build-arg "MODULE=$module" -f "$project_dir/Dockerfile" -t "$repo:$tag" --push "$project_dir"
done
printf '\nImagens publicadas com tag %s. Execute: bash infra/scripts/deploy.sh %s\n' "$tag" "$tag"
