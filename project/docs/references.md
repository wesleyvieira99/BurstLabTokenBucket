# Fontes oficiais do BurstLab

Consultadas em **15 de outubro de 2026**. O conteúdo educacional inclui raciocínio e cálculos próprios a partir das premissas declaradas; os links abaixo sustentam contratos de APIs e serviços. Não apresentamos números ilustrativos como benchmarks.

- [Spring Boot 3.5.7 — release oficial](https://spring.io/blog/2025/10/23/spring-boot-3-5-7-available-now/) — Versão publicada e fixada no projeto. Consulta: 15/10/2026.
- [Spring Boot 3.5 — requisitos](https://docs.spring.io/spring-boot/3.5/system-requirements.html) — Java compatível e ferramentas de build. A página acompanha a linha 3.5; o POM fixa 3.5.7. Consulta: 15/10/2026.
- [Spring Boot — dependências gerenciadas](https://docs.spring.io/spring-boot/3.5/appendix/dependency-versions/coordinates.html) — Conceito de BOM; a resolução exata da entrega vem do parent 3.5.7 e do effective POM. Consulta: 15/10/2026.
- [Spring Boot — graceful shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html) — Encerramento gracioso e janela de conclusão. Consulta: 15/10/2026.
- [Java 17 — HttpClient](https://docs.oracle.com/en/java/javase/17/docs/api/java.net.http/java/net/http/HttpClient.html) — Reuso, send/sendAsync, interrupção e limites do cancelamento. Consulta: 15/10/2026.
- [Java 17 — HttpRequest.Builder](https://docs.oracle.com/en/java/javase/17/docs/api/java.net.http/java/net/http/HttpRequest.Builder.html) — Timeout por requisição e construção de headers/payload. Consulta: 15/10/2026.
- [Redis — scripts Lua](https://redis.io/docs/latest/develop/programmability/eval-intro/) — Atomicidade, EVALSHA, SCRIPT LOAD e volatilidade do cache. Consulta: 15/10/2026.
- [Redis — API Lua](https://redis.io/docs/latest/develop/programmability/lua-api/) — Representação numérica e conversão RESP. Consulta: 15/10/2026.
- [Redis — TIME](https://redis.io/docs/latest/commands/time/) — Tempo do servidor em segundos e microssegundos. Consulta: 15/10/2026.
- [Redis Cluster — especificação](https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/) — Hash slots, hash tags e limitações de consistência/failover. Consulta: 15/10/2026.
- [Lettuce — connection pooling](https://redis.github.io/lettuce/advanced-usage/connection-pooling/) — Conexões thread-safe, de longa duração e quando pooling é útil. Consulta: 15/10/2026.
- [Lettuce — conexão e configuração](https://redis.github.io/lettuce/user-guide/connecting-redis/) — URIs, TLS e configurações de conexão. Consulta: 15/10/2026.
- [SQS — short e long polling](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-short-and-long-polling.html) — Recebimento com espera e redução de consultas vazias. Consulta: 15/10/2026.
- [SQS — visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html) — Invisibilidade temporária, extensão e duplicatas. Consulta: 15/10/2026.
- [SQS — configuração de visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/working-with-visibility-timeouts.html) — Relação entre visibilidade e timeout de leitura do cliente. Consulta: 15/10/2026.
- [SQS — entrega at-least-once](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues-at-least-once-delivery.html) — Duplicação possível e processamento idempotente. Consulta: 15/10/2026.
- [SQS — FIFO](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-fifo-queues.html) — Garantias de fila não são transação ponta a ponta com efeito remoto. Consulta: 15/10/2026.
- [SQS — dead-letter queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html) — Políticas de recebimento e redrive; o projeto usa DLQ explícita por tentativas reais. Consulta: 15/10/2026.
- [AWS — transactional outbox](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html) — Problema de dual write e publicação recuperável. Consulta: 15/10/2026.
- [AWS Builders Library — timeouts, retries e jitter](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/) — Orçamento de tentativas, backoff e efeitos da sincronização. Consulta: 15/10/2026.
- [ElastiCache — versões de engine](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/engine-versions.html) — Redis OSS 7.1 explicitamente identificado; disponibilidade regional deve ser consultada. Consulta: 15/10/2026.
- [ECS — task IAM role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html) — Permissões da aplicação separadas da execution role. Consulta: 15/10/2026.
- [ECS — networking awsvpc](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking-awsvpc.html) — Interfaces de rede das tasks e security groups. Consulta: 15/10/2026.
- [CloudWatch — OpenTelemetry Collector](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-OTLPSimplesetup.html) — Coleta e exportação de telemetria. Consulta: 15/10/2026.
- [PostgreSQL 16 — explicit locking](https://www.postgresql.org/docs/16/explicit-locking.html) — Locks consultivos e escopo transacional da barreira de capacidade em B. Consulta: 15/10/2026.

## Escopo das versões

Java 17 LTS e Spring Boot 3.5.7 estão fixados no projeto. Lettuce 6.6.0.RELEASE vem do BOM desse parent. AWS SDK 2.29.52, Redis local 7.2.7 e PostgreSQL local 16.6 estão fixados nos arquivos de build/configuração; na AWS, a referência usa Redis OSS 7.1 e família PostgreSQL 16. Páginas de documentação de uma linha podem exibir patches posteriores. A versão efetivamente usada é a resolvida pelo POM, imagem e Terraform entregues.

## Limites da evidência

O simulador é didático e não consulta os containers ou a conta AWS. O relatório de verificação da entrega diferencia comandos executados, testes pulados e infraestrutura não provisionada. Preços não são afirmados sem cotação por região e data. A compatibilidade local do emulador SQS não prova equivalência integral com o serviço AWS.
