package br.com.burstlab.common;
import org.junit.jupiter.api.*;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.*;
import io.lettuce.core.RedisClient;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
class RedisLimiterTest {
 static GenericContainer<?> redis;static String testUri;
 @BeforeAll static void start(){testUri=System.getenv("REDIS_TEST_URI");if(testUri==null){Assumptions.assumeTrue(org.testcontainers.DockerClientFactory.instance().isDockerAvailable(),"Docker indisponível; use REDIS_TEST_URI");redis=new GenericContainer<>("redis:7.2.7-alpine").withExposedPorts(6379);redis.start();testUri="redis://"+redis.getHost()+":"+redis.getMappedPort(6379);}}
 @AfterAll static void stop(){if(redis!=null)redis.stop();}
 String uri(){return testUri;}
 RedisLimiter create(String group,double c,double rate,int slots){return new RedisLimiter(uri(),group,c,rate,slots,5000);}
 String group(){return UUID.randomUUID().toString();}
 @Test void fullEmptyAndReleaseDoesNotRefund(){try(var l=create(group(),1,0.001,1)){var a=l.acquire();assertTrue(a.allowed());assertEquals(0,a.remainingTokens(),0.01);l.release(a);var denied=l.acquire();assertFalse(denied.allowed());assertEquals("TOKEN",denied.reason());assertTrue(denied.retryAfterMs()>0);}}
 @Test void partialRefillAndCeiling()throws Exception {try(var l=create(group(),4,2,20)){assertTrue(l.acquire(4).allowed());Thread.sleep(200);var a=l.acquire(0.25);assertTrue(a.allowed());assertTrue(a.remainingTokens()<1);Thread.sleep(2100);var b=l.acquire();assertTrue(b.allowed());assertTrue(b.remainingTokens()<=3.0001);}}
 @Test void invalidAndImpossibleCosts(){try(var l=create(group(),8,32,8)){for(double c:new double[]{0,-1,Double.NaN,Double.POSITIVE_INFINITY})assertThrows(RuntimeException.class,()->l.acquire(c));var a=l.acquire(9);assertFalse(a.allowed());assertEquals(-1,a.retryAfterMs());assertEquals("COST_EXCEEDS_CAPACITY",a.reason());}}
 @Test void invalidConfigurationRejected(){try(var l=create(group(),-1,32,8)){assertThrows(RuntimeException.class,l::acquire);}}
 @Test void expirationOnlyAfterFullRefill()throws Exception{String group=group();try(var l=create(group,1,10,8)){var a=l.acquire();l.release(a);Thread.sleep(1200);var client=RedisClient.create(uri());try(var c=client.connect()){assertEquals(0,c.sync().exists("burstlab:{"+group+"}:bucket:v1"));}finally{client.shutdown();}assertTrue(l.acquire().allowed());}}
 @Test void replicasShareAtomicGlobalBudget()throws Exception {String group=group();try(var one=create(group,8,0.0001,8);var two=create(group,8,0.0001,8)){var pool=Executors.newFixedThreadPool(8);try{List<Callable<Boolean>> calls=new ArrayList<>();for(int i=0;i<64;i++){var l=i%2==0?one:two;calls.add(()->l.acquire().allowed());}long allowed=0;for(var f:pool.invokeAll(calls))if(f.get())allowed++;assertEquals(8,allowed);}finally{pool.shutdownNow();}}}
 @Test void clockRollbackDoesNotPrematurelyExpireBucket(){String group=group();String key="burstlab:{"+group+"}:bucket:v1";try(var l=create(group,1,10,8)){var client=RedisClient.create(uri());try(var c=client.connect()){var time=c.sync().time();double now=Double.parseDouble(time.get(0))*1000+Double.parseDouble(time.get(1))/1000;c.sync().hset(key,Map.of("tokens","0","ts",""+(now+10000)));var a=l.acquire();assertFalse(a.allowed());assertTrue(a.retryAfterMs()>=10000);assertTrue(c.sync().pttl(key)>=10500,"TTL deve incluir relógio futuro + reposição");}finally{client.shutdown();}}}
 @Test void clockRollbackKeepsOlderFutureLeases(){String group=group();String key="burstlab:{"+group+"}:leases:v1";try(var l=create(group,8,32,8)){var client=RedisClient.create(uri());try(var c=client.connect()){var time=c.sync().time();double now=Double.parseDouble(time.get(0))*1000+Double.parseDouble(time.get(1))/1000;c.sync().zadd(key,now+20000,"old-lease");assertTrue(l.acquire().allowed());assertTrue(c.sync().pttl(key)>=20500,"TTL deve preservar lease antiga após retrocesso");}finally{client.shutdown();}}}
 @Test void noScriptRecovered(){try(var l=create(group(),8,32,8)){var client=RedisClient.create(uri());try(var c=client.connect()){c.sync().scriptFlush();}finally{client.shutdown();}assertTrue(l.acquire().allowed());}}
 @Test void configurationDriftRejected(){String group=group();try(var one=create(group,8,32,8);var two=create(group,8,33,8)){one.acquire();assertThrows(RuntimeException.class,two::acquire);}}
 @Test void demonstratesReadModifyWriteRace()throws Exception {var client=RedisClient.create(uri());try(var conn=client.connect()){String key="race:"+group();conn.sync().set(key,"1");var barrier=new CyclicBarrier(8);var pool=Executors.newFixedThreadPool(8);try{List<Callable<Boolean>> calls=new ArrayList<>();for(int i=0;i<8;i++)calls.add(()->{int previous=Integer.parseInt(conn.sync().get(key));barrier.await();if(previous>0){conn.sync().set(key,""+(previous-1));return true;}return false;});int allowed=0;for(var f:pool.invokeAll(calls))if(f.get())allowed++;assertEquals(8,allowed,"um token admitiu 8: corrida real");}finally{pool.shutdownNow();}}finally{client.shutdown();}}
}
