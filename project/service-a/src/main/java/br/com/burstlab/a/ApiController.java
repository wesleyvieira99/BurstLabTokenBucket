package br.com.burstlab.a;
import br.com.burstlab.common.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.*;
@RestController @RequestMapping("/api")
public class ApiController {
 private final RedisLimiter limiter;private final BClient b;private final JobStore jobs;private final MeterRegistry metrics;
 public ApiController(RedisLimiter limiter,BClient b,JobStore jobs,MeterRegistry metrics){this.limiter=limiter;this.b=b;this.jobs=jobs;this.metrics=metrics;}
 @PostMapping("/sync")
 public ResponseEntity<?> sync(@RequestHeader("Idempotency-Key") String key,@RequestBody Payload payload,HttpServletRequest req)throws InterruptedException {
  Payload.key(key);long deadline=System.currentTimeMillis()+2000;long waitUntil=System.nanoTime()+50_000_000;RedisLimiter.Admission a;
  try{
   while(true){a=limiter.acquire();if(a.allowed())break;
    if(System.nanoTime()>=waitUntil||a.retryAfterMs()>50||System.currentTimeMillis()+250>deadline){metrics.counter("burstlab_admission","result","denied").increment();return ResponseEntity.status(429).header("Retry-After",""+Math.max(1,(a.retryAfterMs()+999)/1000)).body(Map.of("error","capacidade global indisponível","retryAfterMs",a.retryAfterMs(),"reason",a.reason()));}
    Thread.sleep(Math.max(1,Math.min(10,a.retryAfterMs())));
   }
  }catch(io.lettuce.core.RedisException e){metrics.counter("burstlab_admission","result","redis_unavailable").increment();return ResponseEntity.status(503).header("Retry-After","1").body(Map.of("error","Redis indisponível; política fail-closed"));}
  metrics.counter("burstlab_admission","result","allowed").increment();
  BClient.Result result=b.call("sync:"+key,payload.value(),req.getAttribute("correlationId").toString(),deadline);
  if(result.certain()){try{limiter.release(a);}catch(Exception ignored){/* lease expira; token nunca é devolvido */}}
  return ResponseEntity.status(result.status()).contentType(MediaType.APPLICATION_JSON).body(result.body());
 }
 @PostMapping("/unprotected")
 public ResponseEntity<?> unprotected(@RequestHeader("Idempotency-Key") String key,@RequestBody Payload payload,HttpServletRequest req){
  if(!Settings.flag("ENABLE_UNPROTECTED"))return ResponseEntity.status(404).build();
  BClient.Result r=b.call("raw:"+Payload.key(key),payload.value(),req.getAttribute("correlationId").toString(),System.currentTimeMillis()+2000);
  return ResponseEntity.status(r.status()).contentType(MediaType.APPLICATION_JSON).body(r.body());
 }
 @PostMapping("/jobs")
 public ResponseEntity<?> async(@RequestHeader("Idempotency-Key") String key,@RequestBody Payload payload,HttpServletRequest req){
  JobStore.Job job=jobs.accept(Payload.key(key),payload.value(),req.getAttribute("correlationId").toString());
  return ResponseEntity.accepted().header("Location","/api/jobs/"+job.id()).body(Map.of("jobId",job.id(),"status",job.status(),"statusUrl","/api/jobs/"+job.id()));
 }
 @GetMapping("/jobs/{id}") public JobStore.Job status(@PathVariable UUID id){return jobs.get(id);}
}
