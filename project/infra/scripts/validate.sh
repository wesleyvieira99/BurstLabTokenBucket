#!/usr/bin/env bash
set -euo pipefail
infra_dir="$(cd "$(dirname "$0")/.." && pwd)"
base="$(terraform -chdir="$infra_dir" output -raw api_url)"
region="$(terraform -chdir="$infra_dir" output -raw region)"
cluster="$(terraform -chdir="$infra_dir" output -raw cluster_name)"
key="$(python3 -c 'import uuid; print(uuid.uuid4())')"
aws ecs wait services-stable --region "$region" --cluster "$cluster" --services service-a service-b worker
printf 'Executando um efeito síncrono idempotente...\n'
sync="$(curl --fail-with-body --silent --show-error --max-time 10 -H 'Content-Type: application/json' -H "Idempotency-Key: aws-sync-$key" -H "X-Correlation-ID: $key" -d '{"value":"validacao-aws"}' "$base/api/sync")"
printf '%s\n' "$sync" | jq .
printf 'Aceitando job e repetindo a mesma criação...\n'
first="$(curl --fail-with-body --silent --show-error --max-time 10 -H 'Content-Type: application/json' -H "Idempotency-Key: aws-job-$key" -d '{"value":"validacao-aws"}' "$base/api/jobs")"
second="$(curl --fail-with-body --silent --show-error --max-time 10 -H 'Content-Type: application/json' -H "Idempotency-Key: aws-job-$key" -d '{"value":"validacao-aws"}' "$base/api/jobs")"
job="$(jq -er .jobId <<<"$first")"
[[ "$job" == "$(jq -er .jobId <<<"$second")" ]] || { echo 'Criação duplicou job' >&2; exit 1; }
for attempt in $(seq 1 65); do
  result="$(curl --fail-with-body --silent --show-error --max-time 10 "$base/api/jobs/$job")"
  state="$(jq -er .status <<<"$result")"
  printf 'job=%s estado=%s\n' "$job" "$state"
  if [[ "$state" == SUCCEEDED ]]; then jq . <<<"$result"; exit 0; fi
  if [[ "$state" == FAILED || "$state" == EXPIRED || "$state" == RESULT_UNKNOWN ]]; then jq . <<<"$result"; exit 1; fi
  sleep 2
done
echo 'Job não concluiu na janela de observação; consulte outbox/logs/fila.' >&2
exit 1
