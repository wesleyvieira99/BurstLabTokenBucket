package br.com.burstlab.common;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.util.UUID;
@Component
public class CorrelationFilter extends OncePerRequestFilter {
 protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain)throws ServletException,IOException {
  String c=request.getHeader("X-Correlation-Id");if(c==null||!c.matches("[A-Za-z0-9._:-]{1,128}"))c=UUID.randomUUID().toString();
  request.setAttribute("correlationId",c);response.setHeader("X-Correlation-Id",c);
  org.slf4j.MDC.put("correlationId",c);
  try{chain.doFilter(request,response);}finally{org.slf4j.MDC.remove("correlationId");}
 }
}
