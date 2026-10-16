package br.com.burstlab.b;
import br.com.burstlab.common.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
@RestController
public class DemoController {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final MeterRegistry metrics;
 private final AtomicInteger calls=new AtomicInteger(),active=new AtomicInteger();
 private volatile int latency=Settings.integer("B_LATENCY_MS",200),capacity=Settings.integer("B_CAPACITY",8),failEvery=Settings.integer("B_FAIL_EVERY",0);
 public DemoController(JdbcTemplate db,TransactionTemplate tx,MeterRegistry metrics){this.db=db;this.tx=tx;this.metrics=metrics;metrics.gauge("burstlab_b_active_local",active);}
 @PostMapping("/api/work")
 public ResponseEntity<?> work(@RequestHeader("Idempotency-Key")String key,@RequestHeader("X-Deadline-Epoch-Ms")long deadline,@RequestBody Payload p){
  Payload.operationKey(key);return tx.execute(status->{
   // Lock is held by PostgreSQL until commit/rollback, not by a client-side lease.
   Boolean own=db.queryForObject("SELECT pg_try_advisory_xact_lock(hashtextextended(?,0))",Boolean.class,key);
   if(!Boolean.TRUE.equals(own))return error(503,"operação idêntica em andamento");
   var existing=db.queryForList("SELECT payload,result FROM b_effects WHERE operation_id=?",key);
   if(!existing.isEmpty()){var row=existing.get(0);if(!row.get("payload").equals(p.value()))return error(409,"mesma chave com payload diferente");metrics.counter("burstlab_b_deduplicated").increment();return ResponseEntity.ok(Map.of("result",row.get("result"),"duplicate",true));}
   boolean acquired=false;for(int slot=0;slot<capacity;slot++){if(Boolean.TRUE.equals(db.queryForObject("SELECT pg_try_advisory_xact_lock(4288,?)",Boolean.class,slot))){acquired=true;break;}}
   if(!acquired){metrics.counter("burstlab_b_rejected").increment();return error(503,"B no limite global");}
   if(deadline<System.currentTimeMillis()+latency)return error(504,"prazo insuficiente em B");
   active.incrementAndGet();try{
    Thread.sleep(latency);
    if(deadline<System.currentTimeMillis())return error(504,"prazo expirou antes do efeito");
    if(failEvery>0&&calls.incrementAndGet()%failEvery==0)return error(503,"falha de demonstração");
    String result="processado:"+p.value();
    db.update("INSERT INTO b_effects(operation_id,payload,result) VALUES (?,?,?)",key,p.value(),result);
    metrics.counter("burstlab_b_effects").increment();return ResponseEntity.ok(Map.of("result",result,"duplicate",false));
   }catch(InterruptedException e){Thread.currentThread().interrupt();status.setRollbackOnly();return error(503,"B interrompido");}finally{active.decrementAndGet();}
  });
 }
 @GetMapping("/api/results/{key}") public ResponseEntity<?> result(@PathVariable String key){
  Payload.operationKey(key);var rows=db.queryForList("SELECT result FROM b_effects WHERE operation_id=?",key);
  return rows.isEmpty()?ResponseEntity.notFound().build():ResponseEntity.ok(Map.of("result",rows.get(0).get("result"),"duplicate",true));
 }
 private ResponseEntity<?> error(int code,String reason){return ResponseEntity.status(code).body(Map.of("error",reason));}
 @GetMapping("/demo/config")public Map<String,Integer> config(){return Map.of("latencyMs",latency,"capacity",capacity,"failEvery",failEvery);}
 @PostMapping("/demo/config")public ResponseEntity<?> config(@RequestBody Map<String,Integer> cfg){
  if(!Settings.flag("ENABLE_DEMO_ADMIN"))return ResponseEntity.status(404).build();
  int l=cfg.getOrDefault("latencyMs",latency),f=cfg.getOrDefault("failEvery",failEvery);
  // Capacity is deployment-wide immutable to avoid replica drift. Set B_CAPACITY at startup.
  if(l<1||l>3000||f<0)return error(400,"latência 1–3000ms; failEvery >= 0");latency=l;failEvery=f;return ResponseEntity.ok(config());
 }
}
