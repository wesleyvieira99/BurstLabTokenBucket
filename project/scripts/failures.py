#!/usr/bin/env python3
"""Testes destrutivos APENAS no Compose local burstlab. Nunca aponta para AWS."""
import json, subprocess, time, uuid
from load import request
A='http://localhost:8080';B='http://localhost:8081'
def cmd(*args):return subprocess.check_output(args,text=True).strip()
def compose(*args):return cmd('docker','compose',*args)
def wait_job(job):
    end=time.monotonic()+125
    while time.monotonic()<end:
        code,data=request(A+'/api/jobs/'+job)
        if data.get('status') in ('SUCCEEDED','FAILED','EXPIRED','RESULT_UNKNOWN'):return data
        time.sleep(1)
    raise AssertionError('job não terminou em 125s')
def submit(key):
    code,data=request(A+'/api/jobs',{'value':'falhas-'+key},key);assert code==202,(code,data);return data['jobId']
def sql(query):return compose('exec','-T','postgres','psql','-U','burstlab','-d','burstlab','-tAc',query)
def health():
    for _ in range(60):
        if request(A+'/actuator/health')[0]==200:return
        time.sleep(1)
    raise AssertionError('A não saudável')
health()
crash=None
try:
    key=str(uuid.uuid4());job=submit(key);assert submit(key)==job
    compose('exec','-T','localstack','awslocal','sqs','send-message','--queue-url','http://localhost:4566/queue/us-east-1/000000000000/burstlab-jobs','--message-body',job)
    assert wait_job(job)['status']=='SUCCEEDED'
    assert sql("SELECT count(*) FROM b_effects WHERE operation_id='job:"+job+"'")=='1'
    print('PASS: mensagem duplicada, único efeito durável')
    compose('stop','redis');time.sleep(1)
    assert request(A+'/api/sync',{'value':'redis-down'},str(uuid.uuid4()))[0]==503
    compose('start','redis');time.sleep(3)
    print('PASS: Redis indisponível -> fail-closed 503; recuperação')
    request(B+'/demo/config',{'latencyMs':1800})
    assert request(A+'/api/sync',{'value':'slow'},str(uuid.uuid4()))[0] in (504,503)
    request(B+'/demo/config',{'latencyMs':200,'failEvery':1})
    failed=wait_job(submit(str(uuid.uuid4())));assert failed['status']=='FAILED' and failed['attempts']==3,failed
    print('PASS: B lento e retentativas limitadas a 3 tentativas reais')
    request(B+'/demo/config',{'latencyMs':200,'failEvery':0})
    compose('stop','worker')
    # Unique local container; intentionally terminates after B's commit before DeleteMessage.
    crash='burstlab-crash-'+uuid.uuid4().hex[:8]
    compose('run','-d','--name',crash,'-e','CRASH_AFTER_B_SUCCESS=true','worker')
    cmd('docker','update','--restart=no',crash)
    job=submit(str(uuid.uuid4()))
    for _ in range(70):
        if cmd('docker','inspect','--format','{{.State.Status}}',crash)=='exited':break
        time.sleep(1)
    assert cmd('docker','inspect','--format','{{.State.ExitCode}}',crash)=='77'
    cmd('docker','rm',crash);compose('start','worker')
    recovered=wait_job(job);assert recovered['status']=='SUCCEEDED',recovered
    assert sql("SELECT count(*) FROM b_effects WHERE operation_id='job:"+job+"'")=='1'
    print('PASS: queda depois de B; redelivery recupera resultado, sem segundo efeito')
    # Backlog recovery, deliberately fewer messages than the 120s deadline budget.
    compose('stop','worker');jobs=[submit(str(uuid.uuid4())) for _ in range(40)];compose('start','worker')
    assert all(wait_job(j)['status']=='SUCCEEDED' for j in jobs)
    print('PASS: recuperação e drenagem de 40 jobs')
finally:
    if crash:subprocess.run(['docker','rm','-f',crash],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    compose('start','redis','worker');request(B+'/demo/config',{'latencyMs':200,'failEvery':0})
