# BurstLab — laboratório Java executável

Exemplo didático de proteção de dependências. Leia também o portal `../index.html`, [AWS](docs/aws.md), [operação](docs/operations.md) e [evidências](VERIFICATION.md). Os serviços A, B e worker são executáveis Spring Boot distintos; `common` contém Lua, admissão, outbox e contratos.

## Cenário e versões

Tráfego normal **20 req/s**; burst **120 req/s por 10 s**. B: latência **200 ms**, capacidade global **8 operações**, capacidade ideal aproximada **40 req/s**. Orçamento de admissão compartilhado entre A e todos os workers: **C=8 tokens, r=32 tokens/s, custo=1, concorrência=8**. A margem de 20% é ilustrativa; medir latência de cauda antes de dimensionar produção. Sync: orçamento **2 s**, espera opcional máxima **50 ms**; async: **120 s** desde a aceitação, até **3 tentativas efetivamente iniciadas contra B**. HTTP a B: conexão **300 ms**, resposta **1000 ms**. Redis: conexão **300 ms**, comando **100 ms**. Lease Redis **5000 ms**; B aceita latência configurável até **3000 ms**.

Versões fixadas: Java **17 LTS** (imagem Temurin **17.0.18_8**), Maven **3.9.9**, Spring Boot **3.5.7**, Lettuce **6.6.0.RELEASE** pelo BOM do Boot, AWS SDK Java **2.29.52**, Testcontainers **1.20.4**, Redis local **7.2.7**, PostgreSQL local **16.6**, LocalStack **4.0.3**, OpenTelemetry Java Agent **2.21.0**. Essas são versões reproduzíveis selecionadas, não uma alegação de que sejam as mais recentes. Antes de produção, atualize patches e avalie advisories; tags Docker podem ser republicadas, portanto registre digests do build homologado. AWS usa o engine Redis OSS informado no Terraform; comandos aqui funcionam também em Redis 7.1.

## Executar localmente

Pré-requisitos: Docker Desktop/Engine com Compose v2, pelo menos 4 GB livres; Python 3.10+ para scripts. Java 17+ e Maven 3.6.3+ somente se compilar fora do Docker.

```sh
cd project
chmod +x scripts/localstack-init.sh
docker compose up --build -d
# Pode levar alguns minutos no primeiro build.
docker compose logs -f service-a service-b worker
```

Em outro terminal:

```sh
curl --fail http://localhost:8080/actuator/health
curl --fail http://localhost:8081/actuator/health
curl -i http://localhost:8080/api/sync \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: pedido-sync-1' \
  -d '{"value":"pedido de exemplo"}'
curl -i http://localhost:8080/api/jobs \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: pedido-async-1' \
  -d '{"value":"pedido de exemplo"}'
# Copie o jobId retornado; Location e statusUrl também indicam a consulta.
curl http://localhost:8080/api/jobs/UUID-RETORNADO
```

Sync retorna `200` com resultado, `429` com `Retry-After` para falta de admissão, `503` para Redis indisponível/B ocupado, `504` para prazo ou transporte. Não muda para async automaticamente. `Retry-After` HTTP é arredondado para segundos; o corpo da rejeição de admissão contém `retryAfterMs` preciso em milissegundos.

Async responde `202` **depois do commit de job + evento outbox** no PostgreSQL, mesmo se SQS estiver temporariamente indisponível. Isso aceita duravelmente o trabalho, não confirma sua conclusão. Estados: `QUEUED → PROCESSING → SUCCEEDED`, ou `FAILED` / `EXPIRED` / `RESULT_UNKNOWN`. Um job pode retornar a `QUEUED` ao aguardar capacidade ou retentativa. Resultado e erro persistem. SQS transporta somente UUID, sem payload.

`Idempotency-Key` externa: 1–120 caracteres `A-Z a-z 0-9 . _ : -`. O mesmo endpoint + chave + payload retorna o mesmo efeito/job; mesma chave e payload diferente retorna `409`. Sync, async e demonstração raw têm namespaces diferentes: reutilizar uma chave entre endpoints não representa a mesma operação. A consulta de jobs e os endpoints não têm autenticação neste laboratório. Na referência AWS, o acesso ALB é restrito ao CIDR configurado. Adicione autenticação/autorização por tenant antes de expor publicamente; UUID não é controle de acesso.

## O que cada arquivo constrói

| Arquivo | Responsabilidade e experimento |
|---|---|
| `common/src/main/resources/lua/admit-v1.lua` | Reposição, débito e limite distribuído de chamadas em um script. Rode os testes Redis reais. |
| `common/src/main/java/br/com/burstlab/common/RedisLimiter.java` | Lettuce compartilhado, EVALSHA, recuperação NOSCRIPT, tempo/filas limitados. Pare Redis e observe 503. |
| `service-a/src/main/java/br/com/burstlab/a/ApiController.java` | Sync com espera limitada, async com aceitação transacional, endpoint didático sem admissão. |
| `common/src/main/java/br/com/burstlab/common/JobStore.java` | Idempotência de aceitação, claim com fencing por owner, tentativas, status/resultado. |
| `common/src/main/java/br/com/burstlab/common/OutboxPublisher.java` | Publicação recuperável com `FOR UPDATE SKIP LOCKED`. Pode duplicar após falha entre SendMessage e commit. |
| `worker/src/main/java/br/com/burstlab/worker/Worker.java` | Long polling 20 s, uma mensagem por slot livre, retries limitados, heartbeat e delete após persistência. |
| `service-b/src/main/java/br/com/burstlab/b/DemoController.java` | Latência/falhas, slots globais PostgreSQL e efeito+resultado idempotentes na mesma transação. |
| `common/src/main/resources/schema.sql` | Tabelas duráveis. `SchemaInitializer` serializa bootstrap entre réplicas com advisory lock. Em produção use migrações versionadas. |

Os fontes são completos e compiláveis. O `B` simula um efeito gravando uma linha `b_effects`: efeito e resultado são a mesma transação. Se trocar esse efeito por pagamento/API externa, uma transação PostgreSQL deixa de abranger o efeito externo; esse destino também precisa aceitar uma chave idempotente ou uma estratégia própria de reconciliação.

## Como a proteção funciona

1. A ou worker pede admissão ao Redis; o payload HTTP continua indo diretamente para B.
2. Lua usa `TIME` do servidor (ms com fração), calcula `min(C, saldo + r × max(0, dt)/1000)`, valida argumentos e configuração e debita somente quando há token **e** vaga distribuída.
3. Cada chamada admitida recebe um UUID numa ZSET de leases. As duas chaves têm hash tag `{service-b}`, requisito para um mesmo slot no Redis Cluster. Este cliente usa conexão Redis standalone/primary; trocar para cluster com sharding exige `RedisClusterClient`, além das hash tags já corretas.
4. B tem uma segunda defesa: até `B_CAPACITY` locks PostgreSQL de transação, compartilhados por **todas as réplicas B**. Um semáforo Java local não seria global. Os slots PostgreSQL não expiram por um TTL arbitrário; terminam com commit, rollback ou perda da sessão. O trabalho/efeito deve ficar no mesmo fluxo transacional.
5. Resposta HTTP definitiva libera a lease Redis. Um timeout de transporte deixa o resultado incerto: a lease aguarda expiração. Tokens **nunca** são devolvidos após a chamada; são permissões de início, não slots reutilizáveis.

O TTL do bucket é `ceil(max(0, timestampAnterior − agora) + C/r × 1000) + 1000 ms`; somente após tempo suficiente para repor um bucket vazio pode recriar cheio. Negativas também atualizam timestamp/TTL, sem reposição duplicada. Em retrocesso do relógio, saldo não aumenta e o timestamp anterior é preservado. O script retorna `{allowed, remainingTokens, retryAfterMs, reason}`; saldo é string decimal para não perder frações em RESP2. Custo > C retorna `retryAfterMs=-1`, impossível sem mudança de configuração. Argumentos não positivos/não finitos e configuração divergente entre réplicas geram erro. O script é pequeno, sem espera; EVALSHA recarrega somente após NOSCRIPT.

**Limites explícitos:** um lease Redis sozinho não garante concorrência física sob pausa de processo maior que TTL. O guard de B limita as transações que executam o efeito. Perda/failover do Redis pode conceder tokens extras e degradar a precisão de taxa, mas não remove o guard de B. Perda de conexão PostgreSQL aborta a transação; código não pode continuar um efeito externo independente. O limite de vazão não garante espaçamento uniforme: a envoltória é `C + r × duração`, a partir de um saldo inicial no máximo C. O teto não é “32 em cada janela de um segundo”.

Falhas/resultado ambíguo Redis usam **fail-closed**: A responde 503, worker aguarda e não inicia B. O pool Lettuce não é necessário para EVALSHA; uma conexão thread-safe multiplexada por processo, sem MULTI/BLPOP, tem ciclo de vida gerenciado. Filas do cliente limitadas em 256. Requisições Tomcat: 64 threads, 64 backlog, 256 conexões; Hikari máximo16 por instância. Escalar réplicas aumenta os pools totais: calcule conexões RDS antes de escalar.

O deadline propagado usa epoch em ms; sincronize relógios (NTP). A espera local curta usa `nanoTime`, HTTP usa timeout relativo. O orçamento de 2s não é garantia de tempo real diante de pausa de JVM/escalonamento, e skew pode afetar deadline propagado. B verifica prazo antes do trabalho e do efeito.

## SQS e recuperação

Fila Standard, entrega pelo menos uma vez. Prefetch = 1 mensagem por worker livre; `WORKER_CONCURRENCY=8` por processo, **não** capacidade global. Visibilidade45s > HTTP/read SQS25s; heartbeat a cada15s estende para45s quando processamento demora. Claim DB35s impede consumo simultâneo rotineiro e `owner` impede que um consumidor antigo confirme o estado de outro. Retries HTTP não automáticos: nova tentativa solicita novo token/vaga.

Sem token: atualiza `next_attempt`, devolve a visibilidade para **1–6 segundos com jitter**, não faz busy-loop nem incrementa `attempts`. Redis indisponível: 2s. Falha real B: backoff exponencial `2^tentativa + jitter(0..1)s`; máximo3 tentativas iniciadas. Prazo conta desde aceitação, incluindo espera. Após esgotar tentativas ou prazo, job terminal + outbox DLQ são gravados na mesma transação; somente depois a mensagem original é apagada. Um vencimento por prazo pode ir à DLQ, mas simples contagem de recebimentos/espera não provoca DLQ.

**Não há RedrivePolicy baseada em ReceiveCount** na fila principal. Um poison message fora do contrato UUID é enviado à DLQ antes do delete; duplicata na DLQ pode ocorrer. Para mensagens legítimas, o estado durável governa retries. B terminou e worker caiu? Redelivery usa a mesma chave `job:UUID`, B retorna resultado persistido, sem segundo efeito. Se houve queda após a última tentativa e antes de persistir resultado, o worker consulta `GET B /api/results/job:UUID` sem executar novo efeito. Resultado durável encontrado confirma SUCCEEDED; ausência/falha de consulta preserva `RESULT_UNKNOWN`, porque ausência neste instante não prova que uma execução antiga não vá retomar. Reconcilie antes de redrive. O redrive mantém chave e não duplica o efeito demonstrativo. Não se promete exactly-once de transporte nem atomicidade entre Redis/SQS/B.

Status terminal vem antes de DeleteMessage. Falha no delete causa nova entrega que lê terminal e apaga novamente. Publicador pode enviar duas vezes quando cai depois de SQS aceitar e antes de marcar outbox; idempotência absorve isso. A e worker compartilham publicador, disputando eventos com SKIP LOCKED. Sem persistência disponível, não há 202.

## Testes e experimentos reproduzíveis

```sh
# Testes unitários + Lua em Redis real via Testcontainers (Docker necessário).
mvn -B -ntp verify
# Alternativa se Redis real já está disponível:
REDIS_TEST_URI=redis://localhost:6379 mvn -B -ntp verify
# Cheque a contagem Skipped: build verde com Redis pulado não prova integração.
python3 scripts/load.py --mode all
python3 scripts/failures.py
```

`RedisLimiterTest`: cheio/vazio, reposição parcial/teto, custo inválido/impossível, expiração, concorrência real em duas instâncias, recuperação NOSCRIPT, drift e corrida intencional read/modify/write (um token permite8 na versão não atômica). Não substitui Redis por mock.

`load.py` envia um fluxo agendado por relógio, com pool cliente limitado; grava CSV bruto e JSON em `results/`. Registra atraso do gerador (`send_lag_ms`), p50/p95 HTTP, códigos e estados finais dos jobs. Se o gerador atrasar, a taxa oferecida não foi alcançada: não trate os números como benchmark da arquitetura. O 202 não é conclusão; veja `job_states` e tempo até drenar. Há 5s de intervalo entre cenários. A fila pode levar mais tempo que a janela de chegada para drenar. Com entrada20/s e saída32/s, backlog880 exige aproximadamente73s após o burst, sem retries/latência extra; bucket inicial8 e efeitos discretos mudam o valor exato.

O cenário raw pula admissão em A, mas **mantém a proteção final de B**: demonstra rejeição/saturação real, não derruba deliberadamente o banco. O simulador do portal também ensina filas internas/timeouts hipotéticos sob ausência total de proteção; não é benchmark deste runtime. O baseline não adiciona retries ocultos.

`failures.py` valida duplicata, Redis indisponível, B lento, retries limitados, queda proposital após commit B antes de DeleteMessage e drenagem. Usa somente Compose local. O teste de queda termina um container com código77; asserções verificam um único efeito. Restaura Redis/worker/config B em `finally`. Pode levar alguns minutos por visibility timeout. Execute sem outra carga concorrente.

```sh
# Degradação determinística, apenas ambiente local:
curl -X POST http://localhost:8081/demo/config -H 'Content-Type: application/json' \
  -d '{"latencyMs":1200,"failEvery":2}'
# Restaurar:
curl -X POST http://localhost:8081/demo/config -H 'Content-Type: application/json' \
  -d '{"latencyMs":200,"failEvery":0}'
# Duplicar workers mantém o mesmo bucket/global8:
docker compose up -d --scale worker=2
# Reprocessar UM job depois de corrigir causa (não perde chave idempotente):
python3 scripts/redrive.py UUID-DO-JOB
# Métricas reais:
curl http://localhost:8080/actuator/prometheus
curl http://localhost:8081/actuator/prometheus
# Inspeção durável:
docker compose exec postgres psql -U burstlab -d burstlab \
  -c 'SELECT status,count(*),max(attempts) FROM jobs GROUP BY status;'
docker compose exec localstack awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/queue/us-east-1/000000000000/burstlab-jobs --attribute-names All
```

`B_CAPACITY` é configurável no deploy, não no endpoint de administração: todas as réplicas devem usar o mesmo valor. O guard usa namespace de locks4288. Alterar C/r/concurrency/lease exige atualizar todas as réplicas de maneira coordenada; `CONFIG_MISMATCH` protege contra drift enquanto o estado anterior existir. Não apague estado sob carga para “corrigir” indisponibilidade: isso concede novo burst.

## Configuração externa

Veja `compose.yaml` para valores locais. AWS usa `REDIS_URI=rediss://…`, `JDBC_URL` com verificação TLS, `JDBC_USERNAME`, `JDBC_PASSWORD`, `SQS_QUEUE_URL`, `SQS_DLQ_URL`, `AWS_REGION`, `SERVICE_B_URL`; sem `SQS_ENDPOINT` usa IAM task role e endpoint AWS. Nunca coloque credenciais reais no Compose/commit. `JAVA_TOOL_OPTIONS=-javaagent:/app/opentelemetry-javaagent.jar …` ativa instrumentação OTel; referência ECS configura collector e CloudWatch. IDs de correlação atravessam A→job→worker→B; não inclua payload sensível em logs. Métricas Micrometer exportam em Prometheus; logs/OTel instrumentam HTTP/JDBC/Redis/SQS.

Encerramento: Spring graceful30s, Compose35s, worker para novos polls e espera operações em andamento até29s; interrupção deixa mensagem redeliverável. Não faz DeleteMessage para uma operação incompleta. Pool HTTP JDK é compartilhado por aplicação; timeout e Tomcat limitam trabalho em voo.

## Erros comuns

- **Connection refused / health falha:** aguarde bootstrap, confira `docker compose ps` e logs; Docker precisa estar iniciado.
- **Redis timeout/503:** confira latência/pool/conectividade antes de elevar timeout; falha fechada é intencional.
- **Fila não existe:** `scripts/localstack-init.sh` deve ser executável; `docker compose restart localstack` roda inicialização idempotente.
- **Porta ocupada:** altere apenas lado esquerdo do mapeamento e URL dos scripts.
- **Nenhum worker conclui:** inspecione credenciais, URL da fila, deadlines, outbox e conexões PostgreSQL.
- **Testes Redis pulados:** inicie Docker ou use REDIS_TEST_URI real. Mock não valida atomicidade.
- **409 de idempotência:** chave identifica um payload; crie nova chave para operação diferente.
- **Espera prolongada:** tokens não reservam fatias para sync/async. O exemplo usa orçamento total compartilhado; uma evolução é alocar sub-buckets de reserva sob o teto global, com transferência controlada e métricas por tenant.

Parar preservando dados: `docker compose down`. **Apagar todos os dados locais do laboratório:** `docker compose down -v`. Não use volumes de produção. Terraform/roteiro AWS estão em `infra/` e `docs/aws.md`; provisionamento pago não foi executado.

## Fontes oficiais consultadas em 15/10/2026

- [Java LTS e roadmap](https://www.oracle.com/java/technologies/java-se-support-roadmap.html): Java17 é LTS; termos de distribuição diferem, a imagem usa Eclipse Temurin.
- [Spring Boot3.5.7 release](https://spring.io/blog/2025/10/23/spring-boot-3-5-7-available-now/) e [requisitos3.5](https://docs.spring.io/spring-boot/3.5/system-requirements.html): compatibilidade Java17+, Maven3.6.3+; a página da linha pode mostrar patch mais recente.
- [Lettuce conexão/pooling](https://redis.github.io/lettuce/advanced-usage/connection-pooling/) e [opções](https://redis.github.io/lettuce/advanced-usage/client-options/): conexão thread-safe e limites de fila/timeouts.
- [Lua Redis](https://redis.io/docs/latest/develop/programmability/eval-intro/), [EVALSHA](https://redis.io/docs/latest/commands/evalsha/), [TIME](https://redis.io/docs/latest/commands/time/), [PEXPIRE](https://redis.io/docs/latest/commands/pexpire/): atomicidade, cache efêmero, relógio e TTL.
- [SQS entrega pelo menos uma vez](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues-at-least-once-delivery.html), [visibility](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html) e [long polling](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-short-and-long-polling.html).
- [PostgreSQL advisory locks](https://www.postgresql.org/docs/16/explicit-locking.html#ADVISORY-LOCKS): locks de transação são liberados ao fim da transação.
- [OpenTelemetry Java Agent2.21.0](https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/tag/v2.21.0).
