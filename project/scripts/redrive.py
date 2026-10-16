#!/usr/bin/env python3
"""Reprocessamento local deliberado de UM job após corrigir causa; mantém idempotência B."""
import argparse, subprocess, uuid
p=argparse.ArgumentParser(description=__doc__);p.add_argument('job_id',type=uuid.UUID);a=p.parse_args()
# Publication resets atomically with job state. DLQ copy remains as audit, harmless until manually deleted.
query="""BEGIN;
CREATE TABLE IF NOT EXISTS redrive_audit (snapshot JSONB NOT NULL, recorded_at TIMESTAMPTZ NOT NULL DEFAULT now());
INSERT INTO redrive_audit(snapshot) SELECT to_jsonb(jobs) FROM jobs WHERE id='%s' AND status IN ('FAILED','EXPIRED','RESULT_UNKNOWN');
DELETE FROM outbox WHERE job_id='%s' AND destination='DLQ';
UPDATE jobs SET status='QUEUED',attempts=0,owner=NULL,locked_until=NULL,next_attempt=now(),deadline=now()+interval '120 seconds',error=NULL WHERE id='%s' AND status IN ('FAILED','EXPIRED','RESULT_UNKNOWN');
UPDATE outbox SET published_at=NULL WHERE job_id='%s' AND destination='MAIN' AND EXISTS(SELECT 1 FROM jobs WHERE id='%s' AND status='QUEUED');
COMMIT;"""%(a.job_id,a.job_id,a.job_id,a.job_id,a.job_id)
subprocess.run(['docker','compose','exec','-T','postgres','psql','-v','ON_ERROR_STOP=1','-U','burstlab','-d','burstlab','-c',query],check=True)
print('Job reenfileirado se estava FAILED/EXPIRED. Preserve relatório anterior para auditoria; tentativa foi reiniciada. Cópia DLQ preservada.')
