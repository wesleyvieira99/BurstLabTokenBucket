package br.com.burstlab.common;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class PayloadTest {
 @Test void boundedPayloadAndSafeKeys(){assertEquals("pedido",new Payload("pedido").value());assertThrows(RuntimeException.class,()->new Payload(""));assertThrows(RuntimeException.class,()->new Payload("a".repeat(1001)));assertThrows(RuntimeException.class,()->Payload.key("a\nInjected: true"));assertThrows(RuntimeException.class,()->Payload.key("a".repeat(129)));}
}
