package br.com.burstlab.a;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;
@SpringBootApplication(scanBasePackages="br.com.burstlab") @EnableScheduling
public class ServiceA { public static void main(String[] args) { SpringApplication.run(ServiceA.class,args); } }
