/* Modelo didático determinístico. Sem rede; um passo = 50 ms de tempo virtual. */
(function (root) {
'use strict';
const DEFAULTS={arrival:20,burst:120,burstDuration:10,bucket:8,refill:32,workers:8,concurrency:8,latency:200,bCapacity:8,timeout:2000,retries:2};
class BurstSimulation {
 constructor(config={}) {this.config={...DEFAULTS,...config};this.mode='sync';this.reset();}
 reset(){this.time=0;this.tokens=Number(this.config.bucket);this.fraction=0;this.nextId=0;this.backlog=[];this.bqueue=[];this.active=[];this.retriesQueue=[];this.visibility=[];this.logical=new Map();this.effects=new Set();this.settled=new Set();this.stats={arrived:0,admitted:0,rejected:0,completed:0,timeouts:0,retries:0,dlq:0,duplicates:0,redisDenied:0};this.latencies=[];this.history=[];this.events=[];this.burstUntil=0;this.redisDown=false;this.degraded=false;this.deadWorkers=0;this.lastSample=0;this.previous={arrived:0,completed:0};this.log('Laboratório reiniciado. Bucket cheio.');}
 setMode(mode){if(!['none','sync','async'].includes(mode))throw Error('Modo inválido');this.mode=mode;this.reset();}
 log(message){this.events.unshift({time:this.time,message});this.events=this.events.slice(0,24);}
 burst(){this.burstUntil=this.time+Number(this.config.burstDuration);this.log(`Burst: ${this.config.burst}/s por ${this.config.burstDuration} s.`);}
 degrade(){this.degraded=!this.degraded;this.log(this.degraded?'B degradado: latência ×3 e capacidade pela metade.':'B recuperado.');}
 toggleRedis(){this.redisDown=!this.redisDown;this.log(this.redisDown?'Redis indisponível: proteção fail-closed.':'Redis disponível.');}
 crash(){if(this.mode!=='async'){this.log('Queda de worker disponível no modo assíncrono.');return;}this.deadWorkers=Math.min(Number(this.config.workers),this.deadWorkers+1);const task=[...this.active,...this.bqueue].find(x=>!x.orphan);if(task){task.orphan=true;this.visibility.push({job:{...task.job},at:this.time+10});this.log(`Worker caiu com job ${task.job.id}. Redelivery em 10 s; efeito de B pode concluir.`);}else this.log('Um worker caiu sem mensagem em andamento.');}
 duplicate(){if(this.mode!=='async'){this.log('Mensagens duplicadas pertencem ao modo assíncrono.');return;}const source=[...this.active,...this.bqueue].map(x=>x.job)[0]||this.backlog[0]||[...this.logical.values()].at(-1);if(source){this.backlog.unshift({...source,ready:this.time});this.stats.duplicates++;this.log(`Cópia do job ${source.id} recebida; chave idempotente preservada.`);}else this.log('Inicie a simulação para criar uma mensagem.');}
 inflight(){return this.active.filter(x=>!x.timedOut&&!x.orphan).length+this.bqueue.filter(x=>!x.timedOut&&!x.orphan).length;}
 remainingWorkers(){return Math.max(0,Number(this.config.workers)-this.deadWorkers);}
 admit(job){const c=this.config;if(this.mode!=='none'){
  if(this.redisDown){this.stats.redisDenied++;return false;}
  const max=this.mode==='async'?Math.min(Number(c.concurrency),this.remainingWorkers()):Number(c.concurrency);
  if(this.inflight()>=max||this.tokens+1e-8<1)return false;
  this.tokens=Math.max(0,this.tokens-1);
 }
 job.attempt++;if(job.attempt>1)this.stats.retries++;this.stats.admitted++;this.bqueue.push({job,start:this.time,deadline:this.time+Number(c.timeout)/1000,timedOut:false,orphan:false,finish:Infinity});return true;}
 fail(job){if(this.settled.has(job.id))return;if(this.time-job.created>=120||job.attempt>=1+Number(this.config.retries)){this.settled.add(job.id);if(this.mode==='async')this.stats.dlq++;return;}
 const hash=((job.id*2654435761+job.attempt*1013904223)>>>0)/4294967296;
 job.ready=this.time+Math.min(8,.25*2**(job.attempt-1))*(.5+hash*.5);
 (this.mode==='async'?this.backlog:this.retriesQueue).push({...job});}
 finish(task){const job=task.job;this.effects.add(job.id);
 if(task.orphan)return;
 if(!task.timedOut&&!this.settled.has(job.id)){this.settled.add(job.id);this.stats.completed++;this.latencies.push((this.time-job.created)*1000);if(this.latencies.length>5000)this.latencies.shift();}}
 step(dt=.05){if(!(dt>0&&dt<=1))throw Error('Passo deve estar entre 0 e 1 s');const c=this.config;this.time+=dt;
 if(!this.redisDown)this.tokens=Math.min(Number(c.bucket),this.tokens+Number(c.refill)*dt);
 // O trabalho de B pode sobreviver ao timeout HTTP; ele continua ocupando capacidade física.
 for(const task of [...this.active,...this.bqueue])if(!task.timedOut&&!task.orphan&&task.deadline<=this.time){task.timedOut=true;this.stats.timeouts++;this.fail(task.job);}
 const done=this.active.filter(x=>x.finish<=this.time+1e-8);this.active=this.active.filter(x=>x.finish>this.time+1e-8);done.forEach(x=>this.finish(x));
 const due=this.visibility.filter(x=>x.at<=this.time);this.visibility=this.visibility.filter(x=>x.at>this.time);due.forEach(x=>{x.job.ready=this.time;this.backlog.push(x.job);this.log(`Job ${x.job.id} reapareceu após visibility timeout.`);});
 const rate=this.time<=this.burstUntil?Number(c.burst):Number(c.arrival);this.fraction+=rate*dt;
 while(this.fraction>=1){this.fraction-=1;const job={id:++this.nextId,created:this.time,attempt:0,ready:this.time};this.logical.set(job.id,job);this.stats.arrived++;
  if(this.mode==='async')this.backlog.push(job);else if(!this.admit(job)){this.stats.rejected++;this.settled.add(job.id);}
 }
 const pending=this.retriesQueue;this.retriesQueue=[];for(const job of pending){if(job.ready>this.time)this.retriesQueue.push(job);else if(!this.admit(job)){this.stats.rejected++;this.settled.add(job.id);}}
 if(this.mode==='async'){
  this.backlog=this.backlog.filter(job=>{if(this.time-job.created>=120&&!this.settled.has(job.id)){this.stats.dlq++;this.settled.add(job.id);return false;}return true;});
  // Só busca trabalho quando há slot e token; espera por capacidade não consome tentativa.
  let budget=this.backlog.length;while(budget--&&this.backlog.length){const job=this.backlog[0];if(job.ready>this.time){this.backlog.push(this.backlog.shift());continue;}if(this.settled.has(job.id)){this.backlog.shift();continue;}if(this.inflight()>=Math.min(Number(c.concurrency),this.remainingWorkers())||this.redisDown||this.tokens<1)break;
   this.backlog.shift();if(this.effects.has(job.id)){this.tokens--;this.stats.admitted++;this.stats.completed++;this.settled.add(job.id);this.latencies.push((this.time-job.created)*1000);this.log(`Resultado persistido do job ${job.id} recuperado sem repetir o efeito.`);}else this.admit(job);
  }
 }
 const capacity=Math.max(1,Math.floor(Number(c.bCapacity)/(this.degraded?2:1)));const duration=Number(c.latency)/1000*(this.degraded?3:1);
 while(this.active.length<capacity&&this.bqueue.length){const task=this.bqueue.shift();task.finish=this.time+duration;this.active.push(task);}
 if(this.time-this.lastSample>=.5-1e-8){const window=this.time-this.lastSample;this.history.push({time:this.time,input:(this.stats.arrived-this.previous.arrived)/window,output:(this.stats.completed-this.previous.completed)/window,backlog:this.backlog.length,tokens:this.tokens,inflight:this.inflight()});this.previous={arrived:this.stats.arrived,completed:this.stats.completed};this.lastSample=this.time;this.history=this.history.slice(-120);}
 return this.snapshot();}
 snapshot(){const latest=this.history.at(-1)||{input:0,output:0};const oldest=this.backlog.length?Math.min(...this.backlog.map(x=>x.created)):this.time;const sorted=[...this.latencies].sort((a,b)=>a-b);return {...this.stats,time:this.time,tokens:this.tokens,backlog:this.backlog.length,inflight:this.inflight(),bActive:this.active.length,bWaiting:this.bqueue.length,input:latest.input,output:latest.output,oldest:this.time-oldest,p95:sorted.length?sorted[Math.ceil(sorted.length*.95)-1]:0,mean:sorted.length?sorted.reduce((a,b)=>a+b,0)/sorted.length:0,effects:this.effects.size,workers:this.remainingWorkers()};}
}
root.BurstSimulation=BurstSimulation;root.BURST_DEFAULTS=DEFAULTS;
if(typeof module!=='undefined')module.exports={BurstSimulation,DEFAULTS};
})(typeof window!=='undefined'?window:globalThis);
