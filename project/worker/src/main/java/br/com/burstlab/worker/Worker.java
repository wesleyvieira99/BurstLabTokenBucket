package br.com.burstlab.worker;
import br.com.burstlab.common.*;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.Message;
import org.springframework.stereotype.Component;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import jakarta.annotation.PreDestroy;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.LoggerFactory;
import java.util.*;
import java.util.concurrent.*;
@Component
public class Worker {
 private final SqsClient sqs;private final JobStore jobs;private final RedisLimiter limiter;private final BClient b;private final MeterRegistry metrics;
 private final int concurrency=Settings.integer("WORKER_CONCURRENCY",8);
 private final ExecutorService pool=Executors.newFixedThreadPool(concurrency);
 private final ScheduledExecutorService heartbeat=Executors.newScheduledThreadPool(1);
 private volatile boolean running=true;private final String queue=Settings.env("SQS_QUEUE_URL","");
 public Worker(SqsClient sqs,JobStore jobs,RedisLimiter limiter,BClient b,MeterRegistry metrics){this.sqs=sqs;this.jobs=jobs;this.limiter=limiter;this.b=b;this.metrics=metrics;}
 @EventListener(ApplicationReadyEvent.class)public void start(){for(int i=0;i<concurrency;i++)pool.submit(this::poll);}
 private void poll(){while(running&&!Thread.currentThread().isInterrupted()){try{
   // Each free worker receives only one message: no unbounded local prefetch.
   var response=sqs.receiveMessage(r->r.queueUrl(queue).maxNumberOfMessages(1).waitTimeSeconds(20).visibilityTimeout(45));
   for(Message message:response.messages())process(message);
  }catch(Exception e){LoggerFactory.getLogger(getClass()).warn("worker aguardará recuperação: {}",e.getClass().getSimpleName());sleep(1000);}}}
 private void process(Message message){UUID id;try{id=UUID.fromString(message.body());}catch(IllegalArgumentException e){
   sqs.sendMessage(r->r.queueUrl(Settings.env("SQS_DLQ_URL","")).messageBody(message.body()));delete(message);return;}
  UUID owner=UUID.randomUUID();JobStore.Job job;
  try{job=jobs.get(id);}catch(org.springframework.web.server.ResponseStatusException e){
   if(e.getStatusCode().value()!=404)throw e;
   sqs.sendMessage(r->r.queueUrl(Settings.env("SQS_DLQ_URL","")).messageBody(message.body()));delete(message);
   LoggerFactory.getLogger(getClass()).warn("job_missing: UUID sem registro durável encaminhado à DLQ");return;
  }
  if(jobs.terminal(job)){delete(message);return;}
  if(!jobs.claim(id,owner)){visibility(message,5);return;}
  job=jobs.get(id);
  if(job.deadline()<=System.currentTimeMillis()){reconcileOrFinish(job,owner,message,"EXPIRED","prazo total de 120s");return;}
  if(job.attempts()>=3){reconcileOrFinish(job,owner,message,"RESULT_UNKNOWN","limite de tentativas; efeito anterior pode ter ocorrido");return;}
  RedisLimiter.Admission admission;
  try{admission=limiter.acquire();}catch(io.lettuce.core.RedisException e){jobs.delay(id,owner,2,"Redis indisponível; fail-closed");visibility(message,2);metrics.counter("burstlab_worker_wait","reason","redis").increment();return;}
  if(!admission.allowed()){
   int delay=(int)Math.max(1,Math.min(5,(admission.retryAfterMs()+999)/1000))+ThreadLocalRandom.current().nextInt(2);
   jobs.delay(id,owner,delay,"espera de capacidade; tentativa não consumida");visibility(message,delay);metrics.counter("burstlab_worker_wait","reason","capacity").increment();return;
  }
  // Visibility can be extended independently; durable DB claim is longer than max HTTP+DB processing.
  var extension=heartbeat.scheduleAtFixedRate(()->{try{visibility(message,45);}catch(Exception e){LoggerFactory.getLogger(getClass()).warn("visibility heartbeat falhou");}},15,15,TimeUnit.SECONDS);
  try{
   int attempts=jobs.beginAttempt(id,owner);
   LoggerFactory.getLogger(getClass()).info("início B jobId={} correlationId={} attempt={}",id,job.correlation(),attempts);
   BClient.Result result=b.call("job:"+id,job.value(),job.correlation(),Math.min(job.deadline(),System.currentTimeMillis()+1500));
   if(result.certain()){try{limiter.release(admission);}catch(Exception ignored){}}
   if(result.status()>=200&&result.status()<300){
    // Local failure lab: terminate precisely after B committed, before job completion/delete.
    if(Settings.flag("CRASH_AFTER_B_SUCCESS"))Runtime.getRuntime().halt(77);
    jobs.success(id,owner,result.body());delete(message);metrics.counter("burstlab_worker_completed").increment();
   }else if(result.status()==409||result.status()==400||attempts>=3){if(!result.certain())reconcileOrFinish(job,owner,message,"RESULT_UNKNOWN",result.body());else{jobs.fail(id,owner,"FAILED",result.body());delete(message);}metrics.counter("burstlab_worker_failed").increment();}
   else{int delay=(1<<attempts)+ThreadLocalRandom.current().nextInt(2);jobs.delay(id,owner,delay,result.body());visibility(message,delay);}
  }finally{extension.cancel(false);}
 }
 private void reconcileOrFinish(JobStore.Job job,UUID owner,Message message,String fallback,String error){
  if(job.attempts()>0){var stored=b.lookup("job:"+job.id());if(stored.status()==200){jobs.success(job.id(),owner,stored.body());delete(message);return;}
   // 404 is not proof of no effect: an old B process might resume later. Preserve uncertainty.
   jobs.fail(job.id(),owner,"RESULT_UNKNOWN",error+"; consulta não confirmou resultado");
  }else jobs.fail(job.id(),owner,fallback,error);
  delete(message);
 }
 private void delete(Message m){sqs.deleteMessage(r->r.queueUrl(queue).receiptHandle(m.receiptHandle()));}
 private void visibility(Message m,int seconds){sqs.changeMessageVisibility(r->r.queueUrl(queue).receiptHandle(m.receiptHandle()).visibilityTimeout(seconds));}
 private void sleep(long ms){try{Thread.sleep(ms);}catch(InterruptedException e){Thread.currentThread().interrupt();}}
 @PreDestroy public void stop(){running=false;pool.shutdown();try{if(!pool.awaitTermination(29,TimeUnit.SECONDS))pool.shutdownNow();}catch(InterruptedException e){pool.shutdownNow();Thread.currentThread().interrupt();}heartbeat.shutdownNow();}
}
