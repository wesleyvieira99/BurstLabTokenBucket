#!/usr/bin/env bash
set -euo pipefail
infra_dir="$(cd "$(dirname "$0")/.." && pwd)"
tag="${1:?Uso: deploy.sh TAG_PUBLICADA}"
region="$(terraform -chdir="$infra_dir" output -raw region)"
repos="$(terraform -chdir="$infra_dir" output -json ecr_repositories)"
for module in service-a service-b worker; do
  repo="$(jq -r --arg module "$module" '.[$module] | split("/")[1:] | join("/")' <<<"$repos")"
  aws ecr describe-images --region "$region" --repository-name "$repo" --image-ids "imageTag=$tag" --query 'imageDetails[0].imageDigest' --output text
done
# Persiste a escolha para próximos plan/apply não destruírem serviços por engano.
jq -n --arg tag "$tag" '{deploy_apps:true,image_tag:$tag}' > "$infra_dir/images.auto.tfvars.json"
terraform -chdir="$infra_dir" plan -out=deploy.tfplan
printf 'O plano acima cria/atualiza recursos pagos. Digite APLICAR para executá-lo: '
read -r answer
[[ "$answer" == APLICAR ]] || { echo 'Plano salvo; nada aplicado.'; exit 0; }
terraform -chdir="$infra_dir" apply deploy.tfplan
cluster="$(terraform -chdir="$infra_dir" output -raw cluster_name)"
aws ecs wait services-stable --region "$region" --cluster "$cluster" --services service-a service-b worker
terraform -chdir="$infra_dir" output api_url
