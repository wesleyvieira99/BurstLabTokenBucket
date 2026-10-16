package br.com.burstlab.b;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;
@SpringBootApplication(scanBasePackages="br.com.burstlab") @EnableScheduling
public class ServiceB { public static void main(String[] args) { SpringApplication.run(ServiceB.class,args); } }
