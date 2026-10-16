# Operação e investigação de falhas

Uma **métrica** mede um conjunto de eventos; um **log** registra um evento; um **trace** liga etapas da mesma operação. Um **SLO** é o objetivo de serviço combinado com o consumidor. Defina separadamente prazo de resposta síncrona e prazo até conclusão assíncrona. 202 não conta como conclusão de B.

## Antes de abrir um incidente

Registre janela de tempo, versão da imagem, tipo sync/async, tenant, correlação e jobId. Não registre payload sensível ou segredo. Compare entrada, admissões, conclusões, retries e erros. Saldo de token não é medida de capacidade de B. Um erro HTTP pode ter ocorrido depois que B confirmou um efeito: consulte o resultado pela mesma chave idempotente antes de tentar novamente.

As métricas SQS são aproximadas; idade da fila é um sinal de espera, não um relógio preciso por job. Compare com o prazo persistido no PostgreSQL, principalmente quando o job ainda está na outbox. SQS vazio não demonstra que não há trabalho pendente: pode haver intenção ainda não publicada ou mensagens invisíveis. [Métricas SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html).

## Backlog cresce continuamente

1. Confirme entrada média, conclusões por segundo, idade do trabalho mais antigo e quantidade de linhas não enviadas da outbox.
2. Se entrada média `λ ≥ μ` (saída sustentável), não existe drenagem sustentada. Reduza admissão de novos jobs, aplique quota por tenant, expire jobs conforme contrato ou aumente a capacidade real de B. A fila é um amortecedor finito, não um gerador de capacidade.
3. Se `λ < μ`, estime `T ≈ backlog/(μ−λ)`. No exemplo: pico120/s, saída32/s durante10s gera cerca de880 trabalhos, ignorando fronteiras e o crédito inicial. Com entrada20/s, drenagem aproximada `880/12 ≈73,3s`. Não apresente esse cálculo como medição.
4. Se tokens sobram e B está ocioso, procure workers sem CPU, pool HTTP/SQL saturado, threads bloqueadas, DNS ou mensagens invisíveis. Aumente workers gradualmente até o teto definido; o orçamento global permanece igual.
5. Se `remainingTokens≈0`, mais workers tendem a aumentar disputas e custo. Investigue a capacidade de B antes de mudar C/r/concorrência.

**Confirmação de recuperação:** idade retorna ao patamar normal, outbox esvazia, entrada e conclusões convergem, sem aumento da DLQ. Um backlog menor acompanhado de DLQ crescente não é recuperação.

## Timeouts aumentando

Distingua timeout de conexão, aquisição Redis, espera de admissão, requisição HTTP e prazo total. Observe p95/p99 de B e pool SQL. Com 200ms médios e8 slots a capacidade teórica é40/s; se B degrada para800ms, cai para10/s. O bucket32/s precisa ser reconfigurado para a nova capacidade ou o semáforo rejeitará/adiará, mesmo havendo tokens.

Aumentar timeout permite que chamadas ocupem recursos por mais tempo; não aumenta processamento. Desative retries excessivos do cliente, reduza entrada, preserve a mesma chave idempotente e respeite Retry-After. Cancelamento local do HTTP não garante que o servidor interrompeu o efeito. A proteção em B continua necessária após o lease expirar. Investigue antes de aumentar o lease: longo demais retarda recuperação de clientes mortos; curto demais admite sobreposição após pausas.

## Redis lento ou indisponível

O exemplo usa **fail-closed**. Sync informa indisponibilidade; async permanece durável e espera. Verifique latência, conexões, CPU do engine, memória, DNS, TLS e logs NOSCRIPT. Cache de scripts é por servidor: após reinício/failover o cliente recarrega o script e tenta EVALSHA novamente. Isso é diferente de repetir uma aquisição que sofreu timeout e teve resultado ambíguo.

Não execute `FLUSHALL`, não recrie o bucket cheio e não devolva tokens de aquisições incertas. `noeviction` evita expulsão silenciosa, mas falta de memória passa a rejeitar gravações; alarme memória e ajuste tamanho/TTL. O Lua é atômico no nó que o executa; replicação assíncrona e failover podem perder estado. Defina uma janela de recuperação conservadora quando houver perda de chaves. B mantém a defesa transacional global e a idempotência. [Garantias e failover Redis](https://redis.io/docs/latest/operate/oss_and_stack/management/replication/).

**Recuperação:** confirme endpoint primário, adquira sob baixa carga, monitore rejeições e p99, retome entrada gradualmente. Não use tráfego de produção para testar failover pela primeira vez.

## DLQ cresce

DLQ significa **fila de trabalhos que exigem investigação**. Primeiro compare motivo terminal, contagem de tentativas reais e prazo; receber sem token não deve ser uma tentativa de B. Não configure redrive automático por ReceiveCount no Terraform deste exemplo. Prefetch limitado impede dezenas de mensagens invisíveis em cada worker.

Receba uma mensagem da DLQ sem apagá-la para inspeção:

```bash
REGION="$(terraform -chdir=infra output -raw region)"
DLQ="$(terraform -chdir=infra output -raw dlq_url)"
aws sqs receive-message --region "$REGION" --queue-url "$DLQ" \
  --max-number-of-messages 1 --wait-time-seconds 10 --visibility-timeout 60
```

Esta leitura temporariamente oculta a mensagem. Preserve MessageId, jobId e a razão. Corrija a causa primeiro. Reprocessamento é uma nova decisão de negócio: se o job está terminal, apenas recolocar a mesma mensagem na fila não reabre seu estado no banco. Nunca faça redrive em massa antes de reparar a política/estado. O laboratório fornece reabertura explícita do mesmo job, preservando sua chave de efeito. No ambiente local execute `python3 scripts/redrive.py UUID`. Na AWS execute `bash infra/scripts/redrive.sh UUID`: ele apresenta confirmação, cria uma tarefa operacional Fargate privada, arquiva o estado anterior em `job_replay_audit` e atualiza job/outbox na mesma transação. A tarefa recebe o segredo RDS pelo ECS, usa TLS verificado e não abre acesso público ao banco. Somente jobs FAILED/EXPIRED/RESULT_UNKNOWN são reabertos. Um novo prazo de120s e o contador de tentativas são deliberadamente reiniciados. RESULT_UNKNOWN significa que não foi possível confirmar se um efeito ocorreu: a recuperação preserva a mesma chave e nunca presume que um timeout desfez o efeito. A cópia DLQ é preservada. Consulte `/api/jobs/UUID` e apague a mensagem DLQ específica somente após confirmar a resolução; repetir a mesma identidade em B recupera um efeito já confirmado sem aplicá-lo novamente.

A API nativa StartMessageMoveTask depende de uma relação de DLQ configurada. Como aqui a aplicação publica a DLQ explicitamente, o runbook usa inspeção e reabertura controlada com outbox; não promete redrive gerenciado automático. [Redrive SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html).

## Worker caiu depois de B concluir

A visibilidade expira e SQS entrega novamente. O worker busca o estado durável, consulta o resultado em B e reapresenta a mesma chave a B se a política permite uma nova tentativa e ainda precisa confirmar e recebe o resultado já gravado. B não aplica o efeito novamente, pois efeito e resultado idempotente estão na mesma transação. Em seguida o worker confirma status e só então executa DeleteMessage. Se qualquer resposta for ambígua, mantém a mensagem para recuperação; não tenta “desfazer” um efeito remotamente sem contrato de compensação.

A idempotência demonstrada vale para os efeitos dentro da transação PostgreSQL. Chamar um processador de pagamento externo dentro dela não o torna atômico: esse destino precisa de chave idempotente própria ou saga/compensação. Uma chave reutilizada com payload diferente deve gerar conflito, não sucesso enganoso.

## Um tenant monopoliza a capacidade

Identifique a distribuição de admitidos, rejeitados e tempo de fila por tenant. O exemplo compartilha um teto global; não implementa fair scheduling e não oferece reserva contratual para sync. Bloqueie/reduza a origem abusiva em uma fronteira autenticada; o laboratório não possui autenticação ou identidade de tenant.

Para uma evolução, use sub-buckets por tenant/classe sob um pai global ou filas separadas com pesos. Faça a decisão conjunta atomicamente e limite cardinalidade/TTL das chaves. Reserva `sync16/s+async16/s`, `4+4` slots conserva os totais32/s e8; empréstimo requer política explícita. Nunca duplique o bucket global em “um para sync” e “um para async”, ambos com32/s.

## AWS: sinais e ações concretas

```bash
REGION="$(terraform -chdir=infra output -raw region)"
CLUSTER="$(terraform -chdir=infra output -raw cluster_name)"
aws ecs describe-services --region "$REGION" --cluster "$CLUSTER" \
  --services service-a service-b worker --query 'services[].{service:serviceName,running:runningCount,desired:desiredCount,events:events[0:3]}'
aws logs tail "/burstlab/$CLUSTER/worker" --region "$REGION" --since 15m --follow
aws cloudwatch describe-alarms --region "$REGION" --alarm-name-prefix "$CLUSTER-"
```

CloudWatch Container Insights cobre CPU/memória; ADOT envia traces para X-Ray e métricas Prometheus selecionadas para namespace BurstLab. Amostragem de traces de10% é configurada: ausência de um trace específico não prova ausência da chamada. Métricas de negócio vêm da aplicação; dados da simulação no navegador são sempre separados.

Alarmes de backlog/idade usam períodos de60s e dois pontos; não reagem instantaneamente a um burst de10s. Capacidade inicial e admissão precisam suportar esse burst. O coletor é sidecar não essencial: sua queda não derruba o serviço, mas remove telemetria. Investigue logs `otel/` e alarmes de ausência de dados no monitoramento que você operar. Sem `alarm_topic_arn`, os alarmes existem no console, mas não notificam pessoas.

## Segurança, manutenção e retenção

Use Secrets Manager; não inclua tokens em logs, state público ou no portal. Segredos injetados pelo ECS são lidos no início da tarefa. Rotação exige novas tarefas ou um cliente que atualize credenciais; este laboratório usa novas tarefas. RDS gerencia sua senha mestre e pode rotacioná-la: acompanhe o evento e redeploy A/B/worker. Em produção separe usuário de migração dos usuários de runtime, implemente refresh e teste a rotação. [Segredos ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data.html).

Não remova registros de idempotência antes da maior janela de replay que aceita (retention SQS, DLQ, backups e reenvios do cliente). Sem um contrato de expiração, uma limpeza “para economizar espaço” pode reintroduzir efeitos duplicados. A demonstração não executa purga automática de efeitos/jobs. Planeje armazenamento, retenção e reconciliação antes de uso contínuo.

Consultas oficiais: 15/10/2026. Os procedimentos descrevem resultados esperados e precisam ser executados e observados no seu ambiente.
