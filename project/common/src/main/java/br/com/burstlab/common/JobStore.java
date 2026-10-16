package br.com.burstlab.common;
import org.springframework.stereotype.Repository;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;
import java.util.*;
@Repository
public class JobStore {
 public record Job(UUID id,String key,String value,String correlation,String status,int attempts,long deadline,String result,String error) {}
 private final JdbcTemplate db; private final TransactionTemplate tx;
 public JobStore(JdbcTemplate db,TransactionTemplate tx){this.db=db;this.tx=tx;}
 public Job get(UUID id){return db.query("SELECT * FROM jobs WHERE id=?",(r,n)->new Job(r.getObject("id",UUID.class),r.getString("request_key"),r.getString("payload"),r.getString("correlation"),r.getString("status"),r.getInt("attempts"),r.getTimestamp("deadline").getTime(),r.getString("result"),r.getString("error")),id).stream().findFirst().orElseThrow(()->new ResponseStatusException(HttpStatus.NOT_FOUND,"job inexistente"));}
 public Job accept(String key,String value,String correlation){return tx.execute(s->{
  UUID id=UUID.randomUUID();int inserted=db.update("INSERT INTO jobs(id,request_key,payload,correlation,deadline) VALUES (?,?,?,?,now()+interval '120 seconds') ON CONFLICT(request_key) DO NOTHING",id,key,value,correlation);
  if(inserted==1)db.update("INSERT INTO outbox(job_id,destination) VALUES (?,'MAIN')",id);
  UUID actual=db.queryForObject("SELECT id FROM jobs WHERE request_key=?",UUID.class,key);Job job=get(actual);
  if(!job.value.equals(value))throw new ResponseStatusException(HttpStatus.CONFLICT,"mesma chave com payload diferente");return job;
 });}
 public boolean claim(UUID id,UUID owner){return db.update("UPDATE jobs SET status='PROCESSING',owner=?,locked_until=now()+interval '35 seconds' WHERE id=? AND status IN ('QUEUED','PROCESSING') AND (locked_until IS NULL OR locked_until<now()) AND next_attempt<=now()",owner,id)==1;}
 public int beginAttempt(UUID id,UUID owner){return db.queryForObject("UPDATE jobs SET attempts=attempts+1 WHERE id=? AND owner=? AND attempts<3 RETURNING attempts",Integer.class,id,owner);}
 public void delay(UUID id,UUID owner,int seconds,String error){db.update("UPDATE jobs SET status='QUEUED',owner=NULL,locked_until=NULL,next_attempt=now()+(? * interval '1 second'),error=? WHERE id=? AND owner=?",seconds,error,id,owner);}
 public void success(UUID id,UUID owner,String result){int n=db.update("UPDATE jobs SET status='SUCCEEDED',result=?,owner=NULL,locked_until=NULL,error=NULL WHERE id=? AND owner=?",result,id,owner);if(n!=1)throw new IllegalStateException("claim perdido");}
 public void fail(UUID id,UUID owner,String status,String error){tx.executeWithoutResult(s->{int n=db.update("UPDATE jobs SET status=?,error=?,owner=NULL,locked_until=NULL WHERE id=? AND owner=?",status,error,id,owner);if(n==1)db.update("INSERT INTO outbox(job_id,destination) VALUES (?,'DLQ') ON CONFLICT DO NOTHING",id);});}
 public boolean terminal(Job job){return Set.of("SUCCEEDED","FAILED","EXPIRED","RESULT_UNKNOWN").contains(job.status);}
}
