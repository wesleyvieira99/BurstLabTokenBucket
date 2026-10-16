package br.com.burstlab.worker;
import br.com.burstlab.common.*;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.Message;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.UUID;
import static org.mockito.Mockito.*;
class WorkerTest {
 @Test void crashAfterThirdSuccessReconcilesBeforeFailure(){
  var sqs=mock(SqsClient.class);var jobs=mock(JobStore.class);var limiter=mock(RedisLimiter.class);var b=mock(BClient.class);
  var id=UUID.randomUUID();var job=new JobStore.Job(id,"key","payload","correlation","PROCESSING",3,System.currentTimeMillis()+10000,null,null);
  when(jobs.get(id)).thenReturn(job);when(jobs.claim(eq(id),any())).thenReturn(true);when(b.lookup("job:"+id)).thenReturn(new BClient.Result(200,"persistido",true));
  var worker=new Worker(sqs,jobs,limiter,b,new SimpleMeterRegistry());try{ReflectionTestUtils.invokeMethod(worker,"process",Message.builder().body(id.toString()).receiptHandle("receipt").build());verify(jobs).success(eq(id),any(),eq("persistido"));verify(jobs,never()).fail(any(),any(),any(),any());verifyNoInteractions(limiter);verify(b,never()).call(any(),any(),any(),anyLong());}finally{worker.stop();}
 }
 @Test void missingResultAfterLastAttemptRemainsUncertain(){
  var sqs=mock(SqsClient.class);var jobs=mock(JobStore.class);var limiter=mock(RedisLimiter.class);var b=mock(BClient.class);
  var id=UUID.randomUUID();var job=new JobStore.Job(id,"key","payload","correlation","PROCESSING",3,System.currentTimeMillis()+10000,null,null);
  when(jobs.get(id)).thenReturn(job);when(jobs.claim(eq(id),any())).thenReturn(true);when(b.lookup("job:"+id)).thenReturn(new BClient.Result(404,"",true));
  var worker=new Worker(sqs,jobs,limiter,b,new SimpleMeterRegistry());try{ReflectionTestUtils.invokeMethod(worker,"process",Message.builder().body(id.toString()).receiptHandle("receipt").build());verify(jobs).fail(eq(id),any(),eq("RESULT_UNKNOWN"),any());verifyNoInteractions(limiter);}finally{worker.stop();}
 }
 @Test void capacityWaitDoesNotConsumeAttempt(){
  var sqs=mock(SqsClient.class);var jobs=mock(JobStore.class);var limiter=mock(RedisLimiter.class);var b=mock(BClient.class);
  var id=UUID.randomUUID();var job=new JobStore.Job(id,"key","payload","correlation","QUEUED",0,System.currentTimeMillis()+10000,null,null);
  when(jobs.get(id)).thenReturn(job);when(jobs.claim(eq(id),any())).thenReturn(true);when(limiter.acquire()).thenReturn(new RedisLimiter.Admission(false,0,31,"TOKEN","lease"));
  var worker=new Worker(sqs,jobs,limiter,b,new SimpleMeterRegistry());try{ReflectionTestUtils.invokeMethod(worker,"process",Message.builder().body(id.toString()).receiptHandle("receipt").build());verify(jobs).delay(eq(id),any(),intThat(n->n>=1&&n<=6),any());verify(jobs,never()).beginAttempt(any(),any());verify(jobs,never()).fail(any(),any(),any(),any());verifyNoInteractions(b);}finally{worker.stop();}
 }
}
