package br.com.burstlab.common;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import software.amazon.awssdk.services.sqs.SqsClient;
import org.slf4j.LoggerFactory;
@Component @ConditionalOnProperty(name="burstlab.queue",havingValue="true",matchIfMissing=true)
public class OutboxPublisher {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final SqsClient sqs;
 public OutboxPublisher(JdbcTemplate db,TransactionTemplate tx,SqsClient sqs){this.db=db;this.tx=tx;this.sqs=sqs;}
 @Scheduled(fixedDelay=100)
 public void publish(){try{for(int i=0;i<20;i++){Boolean sent=tx.execute(status->{var rows=db.queryForList("SELECT id,job_id,destination FROM outbox WHERE published_at IS NULL ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1");if(rows.isEmpty())return false;var row=rows.get(0);
   String url=Settings.env(row.get("destination").equals("DLQ")?"SQS_DLQ_URL":"SQS_QUEUE_URL","");
   if(url.isBlank())throw new IllegalStateException("URL SQS obrigatória");
   sqs.sendMessage(b->b.queueUrl(url).messageBody(row.get("job_id").toString()));
   db.update("UPDATE outbox SET published_at=now() WHERE id=?",row.get("id"));return true;});if(!Boolean.TRUE.equals(sent))break;}}
  catch(Exception e){LoggerFactory.getLogger(getClass()).warn("outbox pendente; recuperação automática: {}",e.getClass().getSimpleName());}}
}
