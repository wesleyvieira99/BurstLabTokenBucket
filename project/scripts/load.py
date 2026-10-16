#!/usr/bin/env python3
"""Carga open-loop real; biblioteca padrão. Mede admissão HTTP e conclusão dos jobs separadamente."""
import argparse, concurrent.futures as cf, csv, json, pathlib, time, urllib.request, urllib.error, uuid

def request(url,body=None,key=None):
    headers={'Content-Type':'application/json'}
    if key: headers['Idempotency-Key']=key
    data=None if body is None else json.dumps(body).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(url,data=data,headers=headers),timeout=3) as r:return r.status,json.load(r)
    except urllib.error.HTTPError as e:
        try: payload=json.load(e)
        except Exception: payload={'error':str(e)}
        return e.code,payload
    except Exception as e:return 0,{'error':str(e)}

def run(args,mode):
    path={'raw':'unprotected','sync':'sync','async':'jobs'}[mode];rows=[];futures=[]
    start=time.monotonic();duration=args.warmup+args.burst_duration+args.after
    def one(index,scheduled):
        sent=time.monotonic();code,body=request(args.url+'/api/'+path,{'value':'load-'+str(index)},str(uuid.uuid4()))
        return {'n':index,'scheduled_s':scheduled,'send_lag_ms':round((sent-start-scheduled)*1000,2),'latency_ms':round((time.monotonic()-sent)*1000,2),'status':code,'jobId':body.get('jobId','')}
    with cf.ThreadPoolExecutor(max_workers=256) as pool:
        at=0.;i=0
        while at<duration:
            time.sleep(max(0,start+at-time.monotonic()));futures.append(pool.submit(one,i,at));i+=1
            rate=args.burst if args.warmup<=at<args.warmup+args.burst_duration else args.normal
            at+=1/rate
        rows=[f.result() for f in futures]
    accepted=[r['jobId'] for r in rows if r['status']==202];terminal={};until=time.monotonic()+130
    while accepted and time.monotonic()<until:
        with cf.ThreadPoolExecutor(max_workers=16) as pool:
            states=list(pool.map(lambda job:(job,request(args.url+'/api/jobs/'+job)),accepted))
        pending=[]
        for job,(code,state) in states:
            if state.get('status') in ('SUCCEEDED','FAILED','EXPIRED','RESULT_UNKNOWN'):terminal[job]=state
            else:pending.append(job)
        accepted=pending
        if accepted:time.sleep(2)
    counts={str(c):sum(r['status']==c for r in rows) for c in sorted(set(r['status'] for r in rows))}
    lat=sorted(r['latency_ms'] for r in rows);report={'mode':mode,'offered':len(rows),'http':counts,'p50_ms':lat[len(lat)//2],'p95_ms':lat[int(len(lat)*.95)],'max_send_lag_ms':max(r['send_lag_ms'] for r in rows),'job_states':{s:sum(j['status']==s for j in terminal.values()) for s in ('SUCCEEDED','FAILED','EXPIRED','RESULT_UNKNOWN')},'jobs_pending_after_130s':len(accepted),'elapsed_s':round(time.monotonic()-start,2),'assumptions':vars(args)}
    out=pathlib.Path(args.output);out.mkdir(exist_ok=True,parents=True)
    with (out/(mode+'.csv')).open('w') as f:w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
    (out/(mode+'.json')).write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mode',choices=['all','raw','sync','async'],default='all');p.add_argument('--url',default='http://localhost:8080');p.add_argument('--normal',type=int,default=20);p.add_argument('--burst',type=int,default=120);p.add_argument('--burst-duration',type=int,default=10);p.add_argument('--warmup',type=int,default=5);p.add_argument('--after',type=int,default=10);p.add_argument('--output',default='results');a=p.parse_args()
    if min(a.normal,a.burst,a.burst_duration,a.warmup,a.after)<1:p.error('valores devem ser positivos')
    for mode in ['raw','sync','async'] if a.mode=='all' else [a.mode]:run(a,mode);time.sleep(5)
