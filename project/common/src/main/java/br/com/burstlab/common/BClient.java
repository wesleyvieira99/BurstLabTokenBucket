package br.com.burstlab.common;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
@Component
public class BClient {
 public record Result(int status,String body,boolean certain) {}
 private final ObjectMapper json; private final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofMillis(300)).build();
 public BClient(ObjectMapper json){this.json=json;}
 public Result lookup(String key){
  try{var request=HttpRequest.newBuilder(URI.create(Settings.env("SERVICE_B_URL","http://localhost:8081")+"/api/results/"+key)).timeout(Duration.ofMillis(500)).GET().build();var r=http.send(request,HttpResponse.BodyHandlers.ofString());return new Result(r.statusCode(),r.body(),true);}
  catch(InterruptedException e){Thread.currentThread().interrupt();return new Result(503,"consulta interrompida",false);}
  catch(Exception e){return new Result(503,"resultado durável não pôde ser consultado",false);}
 }
 public Result call(String key,String value,String correlation,long deadline){
  long remaining=deadline-System.currentTimeMillis();if(remaining<50)return new Result(504,"prazo esgotado antes de B",true);
  try{
   HttpRequest request=HttpRequest.newBuilder(URI.create(Settings.env("SERVICE_B_URL","http://localhost:8081")+"/api/work"))
    .timeout(Duration.ofMillis(Math.min(1000,remaining))).header("Content-Type","application/json")
    .header("Idempotency-Key",key).header("X-Correlation-Id",correlation).header("X-Deadline-Epoch-Ms",""+deadline)
    .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(new Payload(value)))).build();
   HttpResponse<String> response=http.send(request,HttpResponse.BodyHandlers.ofString());return new Result(response.statusCode(),response.body(),true);
  }catch(InterruptedException e){Thread.currentThread().interrupt();return new Result(503,"operação cancelada; resultado pode ser incerto",false);}
  catch(Exception e){return new Result(504,"timeout/falha de transporte; resultado de B incerto",false);}
 }
}
