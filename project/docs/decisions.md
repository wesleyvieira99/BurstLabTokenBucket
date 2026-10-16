# Decisões arquiteturais do BurstLab

Premissas de ensino: entrada normal **20 trabalhos/s**, pico **120/s por 10 s**, B com **200 ms** médios e **8 operações simultâneas**, capacidade teórica `8 / 0,2 = 40/s`. Reservamos margem: bucket global `C=8`, reposição `r=32 tokens/s`, custo `1`, concorrência global `8`. Esses valores são configuração e modelo, não resultados de benchmark.

## ADR 01 — Admissão global antes de B

**Problema:** cada réplica localmente “segura” pode sobrecarregar B quando as taxas se somam. **Alternativas:** semáforo local, gateway central, Lua em Redis, limitador no próprio B. **Escolha:** script Redis para decisão atômica de tokens e leases compartilhados entre A e workers; defesa independente de concorrência em B. **Consequência:** nenhuma réplica multiplica o orçamento. Redis entra na decisão, enquanto o payload segue por HTTP. **Rever:** se a latência de Redis superar o orçamento de admissão, se um único hash slot saturar, ou se B oferecer limites nativos suficientes.

## ADR 02 — Token e lease têm significados diferentes

**Problema:** limitar taxa não limita chamadas lentas em andamento. **Alternativas:** só token bucket, só semáforo, ambos. **Escolha:** cada tentativa consome um token, e ocupa uma permissão de concorrência identificada com prazo de lease. Ao terminar libera-se o lease; o token continua gasto. **Consequência:** atraso/retry exige uma nova aquisição. Leases expiram para recuperar clientes mortos, mas uma pausa longa de JVM pode fazer um detentor “morto” continuar executando. A expiração não prova cancelamento do trabalho. **Rever:** usar fencing validado no destino ou um coordenador com semântica apropriada quando os efeitos saírem da transação protegida de B.

## ADR 03 — Fail-closed e defesa no destino

**Problema:** timeout em Redis deixa a aquisição ambígua; failover pode perder débitos/leases. **Alternativas:** fail-open, cache de permissões locais, fail-closed. **Escolha:** fail-closed: A retorna indisponibilidade e workers adiam. Nunca devolver um token cuja aquisição é incerta. B usa slots globais PostgreSQL via locks transacionais para seu limite efetivo. **Consequência:** falha do limitador reduz disponibilidade. Reposição de estado após failover pode exceder a taxa nominal, embora B ainda se defenda da concorrência. **Rever:** negócio que aceita explicitamente sobrecarga limitada pode reservar um orçamento local de emergência previamente particionado. Não ativar fail-open improvisado durante incidente.

## ADR 04 — PostgreSQL e outbox

**Problema:** gravar status e publicar SQS são duas operações em sistemas diferentes. **Alternativas:** publicar antes/depois, transação distribuída, outbox, DynamoDB com Streams. **Escolha:** persistir job e intenção de publicação na mesma transação PostgreSQL, responder 202 após commit, publicar por dispatcher e marcar envio depois. **Consequência:** um crash entre SendMessage e confirmação no banco pode duplicar mensagens. A chave idempotente precisa sobreviver ao reprocessamento, e B grava efeito e resposta na mesma transação. 202 significa aceitação durável no banco, não execução nem entrega imediata no SQS. **Rever:** quando o volume da outbox justificar CDC ou quando o domínio já tiver DynamoDB/Streams. [Padrão oficial AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html).

## ADR 05 — SQS Standard e DLQ explícita

**Problema:** redrive por quantidade de recebimentos confunde espera por capacidade com falha de negócio. **Alternativas:** `maxReceiveCount`, fila por classe, despacho controlado, DLQ explícita. **Escolha:** contar tentativas reais contra B no banco; o consumidor muda visibilidade com atraso e jitter quando não obtém capacidade; erros terminais e prazo esgotado geram intenção durável de envio à DLQ. A fila principal não configura `redrive_policy`. **Consequência:** exige código e monitoramento próprios; corrupção de mensagens deve ser tratada pelo consumidor; retenção ainda é finita. Não existe garantia de “exactly once” entre SQS e HTTP nem ao trocar para FIFO. **Rever:** se um despachante pré-admissão garantir que cada receive corresponde a uma tentativa válida, redrive automático poderá voltar a ser adequado. [Visibilidade e redelivery](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html).

## ADR 06 — Compartilhamento entre sync, async e tenants

**Problema:** um bucket global protege B, mas não garante justiça nem reserva para o síncrono. **Alternativas:** first-come-first-served, quotas fixas, filas ponderadas, sub-buckets com teto global. **Escolha no exemplo:** um orçamento global compartilhado, atendimento oportunista, sem promessa de fairness. A demonstração não implementa identidade de tenant: as chaves de idempotência pertencem ao mesmo laboratório. Uma evolução multitenant deve autenticar a origem e incluir o tenant no escopo dessas chaves. **Consequência:** um fluxo pode prejudicar o outro, inclusive quando há tokens disponíveis apenas em instantes favoráveis. **Rever:** adicionar garantia contratual de latência exige reserva explícita, por exemplo `sync=16/s`, `async=16/s` e `4+4` slots, sempre sob o teto global. Para empréstimo de capacidade, realizar a decisão de reserva e teto global no mesmo script/slot; executar “pega no global, depois tenta no tenant” desperdiça orçamento. Em Cluster, usar hash tag comum `{b}` em todas as chaves consultadas no mesmo script. Quotas por tenant sem teto global também não protegem B.

## ADR 07 — Réplicas não criam capacidade downstream

**Problema:** um backlog alto incentiva aumentar workers indefinidamente. **Alternativas:** CPU target tracking, backlog por worker, idade da fila com teto, ajustar capacidade de B. **Escolha:** 1–4 tarefas worker, 4 consumidores por tarefa, teto global de 8 e 32/s mantido. Alarmes de backlog e idade adicionam uma tarefa com cooldown; fila vazia por cinco períodos permite reduzir. **Consequência:** mais workers ajudam quando falta paralelismo/uma tarefa falha; deixam de ajudar quando B ou o bucket já está saturado. **Rever:** aumentar `r` e concorrência somente com evidência de capacidade adicional de B, cauda de latência e recursos, nunca só porque a fila cresceu.

## ADR 08 — Redis OSS explícito

**Problema:** serviços “compatíveis com Redis” podem ter engines, comportamento e licenciamento diferentes. **Alternativas:** Redis OSS 7.1 no ElastiCache, Valkey, Redis local, MemoryDB. **Escolha:** Terraform declara `engine="redis"`, `engine_version="7.1"`, um primário e uma réplica, TLS, AUTH, `noeviction`. **Consequência:** AWS gerencia patches e failover, sem tornar a replicação síncrona ou o limitador linearizável durante falhas. Local usa Redis real com os comandos equivalentes. **Rever:** Valkey pode ser uma escolha apropriada após testar Lua, failover, cliente e custos; seria uma migração de engine documentada. [Versões oficiais](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/engine-versions.html).

## ADR 09 — Fronteira do laboratório AWS

**Problema:** demonstrar uma arquitetura completa sem esconder complexidade de produção. **Escolha:** subnets privadas, SG por papel, ALB HTTPS restrito ao CIDR informado, RDS TLS com validação, Redis TLS, Secrets Manager, logs e traces. Um NAT e RDS single-AZ são os padrões do laboratório; é possível ativar `rds_multi_az=true`. **Consequência:** não é um ambiente de produção pronto: sem autenticação do domínio, sem mTLS interno, e usuário de banco também executa criação de schema. **Rever antes de produção:** identidade/autorização de tenant, migrações separadas, roles SQL mínimas por serviço, rotação com refresh, VPC endpoints/NAT por AZ, TLS entre serviços, capacidade/backups testados, orçamento e paging. Essa fronteira é explícita e não impede o fluxo executável de ensino.

Consultas oficiais: 15/10/2026. Nenhuma decisão substitui medir o próprio sistema ou testar seus modos de falha.
