#!/usr/bin/env bash
set -euo pipefail
infra_dir="$(cd "$(dirname "$0")/.." && pwd)"
job_id="${1:?Uso: redrive.sh UUID_DO_JOB_TERMINAL}"
[[ "$job_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { echo 'UUID inválido' >&2; exit 2; }
region="$(terraform -chdir="$infra_dir" output -raw region)"
cluster="$(terraform -chdir="$infra_dir" output -raw cluster_name)"
task_def="$(terraform -chdir="$infra_dir" output -raw maintenance_task_definition)"
network="$(terraform -chdir="$infra_dir" output -json maintenance_network)"
printf 'Reabrir job %s em %s, preservar chave de efeito e a cópia DLQ.\n' "$job_id" "$cluster"
printf 'Esta tarefa Fargate é paga. Causa corrigida e auditoria revisada? Digite REPROCESSAR: '
read -r answer
[[ "$answer" == REPROCESSAR ]] || exit 0
# O UUID é estritamente validado. Auditoria durável e reabertura na mesma transação.
sql="BEGIN;
SELECT pg_advisory_xact_lock(108845);
CREATE TABLE IF NOT EXISTS job_replay_audit (audit_id bigserial PRIMARY KEY, recorded_at timestamptz NOT NULL DEFAULT now(), previous_state jsonb NOT NULL);
SELECT id FROM jobs WHERE id='$job_id' FOR UPDATE;
INSERT INTO job_replay_audit(previous_state) SELECT to_jsonb(jobs) FROM jobs WHERE id='$job_id' AND status IN ('FAILED','EXPIRED','RESULT_UNKNOWN');
DELETE FROM outbox WHERE job_id='$job_id' AND destination='DLQ' AND EXISTS(SELECT 1 FROM jobs WHERE id='$job_id' AND status IN ('FAILED','EXPIRED','RESULT_UNKNOWN'));
UPDATE outbox SET published_at=NULL WHERE job_id='$job_id' AND destination='MAIN' AND EXISTS(SELECT 1 FROM jobs WHERE id='$job_id' AND status IN ('FAILED','EXPIRED','RESULT_UNKNOWN'));
UPDATE jobs SET status='QUEUED',attempts=0,owner=NULL,locked_until=NULL,next_attempt=now(),deadline=now()+interval '120 seconds',error=NULL WHERE id='$job_id' AND status IN ('FAILED','EXPIRED','RESULT_UNKNOWN');
COMMIT;"
overrides="$(jq -n --arg sql "$sql" '{containerOverrides:[{name:"maintenance",environment:[{name:"REPLAY_SQL",value:$sql}]}]}')"
result="$(aws ecs run-task --region "$region" --cluster "$cluster" --task-definition "$task_def" --launch-type FARGATE --platform-version 1.4.0 --network-configuration "$network" --overrides "$overrides")"
[[ "$(jq '.failures | length' <<<"$result")" == 0 ]] || { jq '.failures' <<<"$result"; exit 1; }
task="$(jq -er '.tasks[0].taskArn' <<<"$result")"
aws ecs wait tasks-stopped --region "$region" --cluster "$cluster" --tasks "$task"
result="$(aws ecs describe-tasks --region "$region" --cluster "$cluster" --tasks "$task")"
jq '.tasks[0] | {stoppedReason,containers:[.containers[]|{name,exitCode,reason}]}' <<<"$result"
[[ "$(jq -r '.tasks[0].containers[] | select(.name=="maintenance") | .exitCode' <<<"$result")" == 0 ]]
printf 'Confira status pela API e logs maintenance; a mensagem DLQ foi preservada.\n'
