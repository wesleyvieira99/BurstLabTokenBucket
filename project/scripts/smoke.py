#!/usr/bin/env python3
"""Smoke HTTP real, sem dependências Python. Aceita duas réplicas A via --second-url."""
import argparse, concurrent.futures as cf, json, time, uuid
from load import request
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',default='http://localhost:8080');p.add_argument('--b-url',default='http://localhost:8081');p.add_argument('--second-url');p.add_argument('--outbox-only',action='store_true');a=p.parse_args()
for url in [a.url,a.b_url]:assert request(url+'/actuator/health')[0]==200,url
key=str(uuid.uuid4())
first=request(a.url+'/api/sync',{'value':'idempotente'},key);assert first[0]==200,first
second=request(a.url+'/api/sync',{'value':'idempotente'},key);assert second[0]==200 and second[1]['duplicate'],second
assert request(a.url+'/api/sync',{'value':'diferente'},key)[0]==409
print('PASS sync200, idempotência, conflito409')
time.sleep(1)
urls=[a.url,a.second_url or a.url]
with cf.ThreadPoolExecutor(max_workers=32) as pool:
    results=list(pool.map(lambda n:request(urls[n%2]+'/api/sync',{'value':'burst'},str(uuid.uuid4()))[0],range(64)))
assert 429 in results and 200 in results,results
print('PASS burst com orçamento compartilhado; códigos reais:',{str(c):results.count(c) for c in sorted(set(results))})
key=str(uuid.uuid4());r=request(a.url+'/api/jobs',{'value':'duravel'},key);assert r[0]==202,r
assert request(a.url+'/api/jobs',{'value':'duravel'},key)[1]['jobId']==r[1]['jobId']
assert request(a.url+'/api/jobs',{'value':'outro'},key)[0]==409
job=r[1]['jobId']
if not a.outbox_only:
    end=time.monotonic()+125
    while time.monotonic()<end:
        state=request(a.url+'/api/jobs/'+job)[1]
        if state.get('status')=='SUCCEEDED':break
        if state.get('status') in ('FAILED','EXPIRED','RESULT_UNKNOWN'):raise AssertionError(state)
        time.sleep(1)
    else:raise AssertionError('job não concluiu')
print('PASS aceitação202, idempotência de job e conflito409; jobId='+job)
request(a.b_url+'/demo/config',{'latencyMs':1800})
try:
    code,body=request(a.url+'/api/sync',{'value':'slow'},str(uuid.uuid4()));assert code in (504,503),(code,body)
    print('PASS B lento: HTTP',code)
finally:request(a.b_url+'/demo/config',{'latencyMs':200,'failEvery':0})
