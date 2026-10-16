#!/usr/bin/env bash
set -euo pipefail
infra_dir="$(cd "$(dirname "$0")/.." && pwd)"
cluster="$(terraform -chdir="$infra_dir" output -raw cluster_name)"
region="$(terraform -chdir="$infra_dir" output -raw region)"
repos="$(terraform -chdir="$infra_dir" output -json ecr_repositories)"
printf 'Será removida a infraestrutura %s e as imagens ECR. RDS terá snapshot final.\n' "$cluster"
printf 'A fila e seus trabalhos serão excluídos. Exporte resultados antes.\n'
terraform -chdir="$infra_dir" plan -var=deletion_protection=false -out=unlock.tfplan
printf 'Para desativar proteção e preparar a limpeza, digite o nome do cluster: '
read -r answer
[[ "$answer" == "$cluster" ]] || exit 0
terraform -chdir="$infra_dir" apply unlock.tfplan
# ECR force_delete=false: exclusão das imagens é explícita e restrita ao projeto.
for module in service-a service-b worker; do
  repo="$(jq -r --arg module "$module" '.[$module] | split("/")[1:] | join("/")' <<<"$repos")"
  while true; do
    ids="$(aws ecr list-images --region "$region" --repository-name "$repo" --max-results 100 --no-paginate --query imageIds --output json)"
    [[ "$(jq length <<<"$ids")" -gt 0 ]] || break
    aws ecr batch-delete-image --region "$region" --repository-name "$repo" --image-ids "$ids" --output json
  done
done
terraform -chdir="$infra_dir" destroy -var=deletion_protection=false
printf 'Revise snapshots RDS, backups retidos e a janela de recuperação dos segredos.\n'
printf 'O snapshot final continua armazenado e pode gerar cobrança. Não apague o state antes de concluir.\n'
