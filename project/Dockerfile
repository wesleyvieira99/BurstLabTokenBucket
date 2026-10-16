FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /src
COPY pom.xml ./
COPY common common
COPY service-a service-a
COPY service-b service-b
COPY worker worker
ARG MODULE=service-a
RUN mvn -B -ntp -pl ${MODULE} -am -DskipTests package && cp ${MODULE}/target/${MODULE}-1.0.0.jar /app.jar
RUN curl -fL --retry 3 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /rds-global-bundle.pem && curl -fL --retry 3 https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.21.0/opentelemetry-javaagent.jar -o /opentelemetry-javaagent.jar && echo "5b35ccc6c275fd477a06db01923813e13d99c1a52a20b0ea8ed6576eae177c7d  /opentelemetry-javaagent.jar" | sha256sum -c -
FROM eclipse-temurin:17.0.18_8-jre-jammy
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app.jar /app/app.jar
COPY --from=build /rds-global-bundle.pem /app/rds-global-bundle.pem
COPY --from=build /opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar
USER 10001:10001
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -XX:ActiveProcessorCount=2"
ENTRYPOINT ["java","-jar","/app/app.jar"]
