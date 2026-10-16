package br.com.burstlab.common;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.auth.credentials.*;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import java.time.Duration;
import java.net.URI;
@Configuration
public class CommonConfiguration {
 @Bean(destroyMethod="close") @ConditionalOnProperty(name="burstlab.admission",havingValue="true",matchIfMissing=true)
 public RedisLimiter limiter(){return new RedisLimiter(Settings.env("REDIS_URI","redis://localhost:6379"),"service-b",Settings.integer("LIMITER_CAPACITY",8),Settings.integer("LIMITER_RATE",32),Settings.integer("LIMITER_CONCURRENCY",8),Settings.integer("LIMITER_LEASE_MS",5000));}
 @Bean(destroyMethod="close") @ConditionalOnProperty(name="burstlab.queue",havingValue="true",matchIfMissing=true)
 public SqsClient sqs(){var b=SqsClient.builder().region(Region.of(Settings.env("AWS_REGION","us-east-1"))).httpClientBuilder(UrlConnectionHttpClient.builder().connectionTimeout(Duration.ofSeconds(2)).socketTimeout(Duration.ofSeconds(25))).overrideConfiguration(ClientOverrideConfiguration.builder().apiCallTimeout(Duration.ofSeconds(28)).apiCallAttemptTimeout(Duration.ofSeconds(26)).build());
  String endpoint=System.getenv("SQS_ENDPOINT");if(endpoint!=null&&!endpoint.isBlank())b.endpointOverride(URI.create(endpoint)).credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create("test","test")));
  return b.build();}
}
