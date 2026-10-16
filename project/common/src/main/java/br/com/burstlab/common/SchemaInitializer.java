package br.com.burstlab.common;
import jakarta.annotation.PostConstruct;
import javax.sql.DataSource;
import org.springframework.stereotype.Component;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ScriptUtils;
@Component
public class SchemaInitializer {
 private final DataSource dataSource;
 public SchemaInitializer(DataSource dataSource){this.dataSource=dataSource;}
 @PostConstruct public void initialize()throws Exception {
  try(var connection=dataSource.getConnection();var statement=connection.createStatement()){
   statement.execute("SELECT pg_advisory_lock(108844)");
   try{ScriptUtils.executeSqlScript(connection,new ClassPathResource("schema.sql"));}
   finally{statement.execute("SELECT pg_advisory_unlock(108844)");}
  }
 }
}
