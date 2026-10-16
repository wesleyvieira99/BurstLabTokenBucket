package br.com.burstlab.common;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;
public record Payload(String value) {
 public Payload { if(value==null||value.isBlank()||value.length()>1000)throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"value deve conter de 1 a 1000 caracteres"); }
 public static String key(String key){if(key!=null&&key.length()>120)throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"chave externa deve ter até 120 caracteres");return operationKey(key);}
 public static String operationKey(String key){if(key==null||!key.matches("[A-Za-z0-9._:-]{1,128}"))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Idempotency-Key inválido (1–128 caracteres seguros)");return key;}
}
