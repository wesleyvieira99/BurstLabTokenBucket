package br.com.burstlab.common;
import io.lettuce.core.*;
import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.resource.DefaultClientResources;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
public final class RedisLimiter implements AutoCloseable {
 public record Admission(boolean allowed,double remainingTokens,long retryAfterMs,String reason,String leaseId) {}
 private final RedisClient client; private final StatefulRedisConnection<String,String> connection;
 private final DefaultClientResources resources; private final String script; private volatile String sha;
 private final String bucket,leases; private final double capacity,rate; private final int concurrency,leaseMs;
 public RedisLimiter(String uri,String group,double capacity,double rate,int concurrency,int leaseMs) {
  this.capacity=capacity;this.rate=rate;this.concurrency=concurrency;this.leaseMs=leaseMs;
  bucket="burstlab:{"+group+"}:bucket:v1";leases="burstlab:{"+group+"}:leases:v1";
  resources=DefaultClientResources.builder().ioThreadPoolSize(2).computationThreadPoolSize(2).build();
  RedisURI redisUri=RedisURI.create(uri);redisUri.setTimeout(Duration.ofMillis(100));
  client=RedisClient.create(resources,redisUri);
  client.setOptions(ClientOptions.builder().disconnectedBehavior(ClientOptions.DisconnectedBehavior.REJECT_COMMANDS).requestQueueSize(256).socketOptions(SocketOptions.builder().connectTimeout(Duration.ofMillis(300)).build()).timeoutOptions(TimeoutOptions.enabled(Duration.ofMillis(100))).build());
  connection=client.connect();
  try(var stream=getClass().getResourceAsStream("/lua/admit-v1.lua")){script=new String(Objects.requireNonNull(stream).readAllBytes(),StandardCharsets.UTF_8);}catch(IOException e){throw new IllegalStateException(e);}
  sha=connection.sync().scriptLoad(script);
 }
 public Admission acquire(){return acquire(1);}
 public Admission acquire(double cost){
  String id=UUID.randomUUID().toString(); List<Object> result;
  String[] keys={bucket,leases};String[] args={""+capacity,""+rate,""+cost,""+concurrency,""+leaseMs,id};
  try{result=connection.sync().evalsha(sha,ScriptOutputType.MULTI,keys,args);}
  catch(RedisNoScriptException e){sha=connection.sync().scriptLoad(script);result=connection.sync().evalsha(sha,ScriptOutputType.MULTI,keys,args);}
  return new Admission(((Number)result.get(0)).longValue()==1,Double.parseDouble(result.get(1).toString()),((Number)result.get(2)).longValue(),result.get(3).toString(),id);
 }
 public void release(Admission admission){if(admission.allowed())connection.sync().zrem(leases,admission.leaseId());}
 public void close(){connection.close();client.shutdown();resources.shutdown();}
}
