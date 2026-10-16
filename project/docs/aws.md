# Reproduzir o BurstLab na AWS

O objetivo é executar o mesmo fluxo Java, com infraestrutura declarada e observável. Os comandos de criação abaixo são para o leitor executar em sua conta. A entrega não provisionou recursos pagos nem mediu desempenho AWS.

## 1. O que será criado e por quê

| Componente | Configuração do laboratório | Responsabilidade |
| --- | --- | --- |
| Rede | VPC, 2 subnets públicas, 2 privadas em AZs distintas, 1 NAT | Aplicações/bancos sem IP público; saída HTTPS às APIs AWS |
| Entrada | ALB HTTPS443 com certificado ACM existente e DNS Route53 | Publicar apenas `/api/*`; SG aceita o CIDR informado |
| Serviço A | ECS Fargate, 2 tarefas de0,5vCPU/1GiB | Sync, aceitação durável de jobs, consulta, outbox |
| Serviço B | ECS Fargate, 1 tarefa de0,5vCPU/1GiB | Latência200ms, capacidade8, efeito idempotente |
| Workers | ECS Fargate, 2 tarefas inicialmente, 4 consumidores cada | SQS, admissão global, chamada B e conclusão |
| Redis | ElastiCache **Redis OSS7.1**, primário+réplica `cache.t4g.small` | Estado do token bucket e leases; TLS/AUTH/noeviction |
| Persistência | RDS PostgreSQL16, `db.t4g.small`, 20GiB gp3, crescimento até100GiB | Jobs, outbox, efeito/resultado idempotente, defesa de B |
| Filas | SQS Standard, retenção4dias; DLQ14dias | Trabalhos e falhas terminais; criptografia SQS gerenciada |
| Observabilidade | CloudWatch Logs14dias, dashboard, alarmes, ADOT sidecar | Logs, métricas reais e traces amostrados X-Ray |
| Operação | Definição de tarefa manutenção, sem tarefa ativa | Reabrir um job com auditoria e acesso privado ao RDS |

`Terraform >=1.13.3,<2`, provider AWS **6.44.0**, random **3.7.2**, ADOT collector **v0.43.3**. `.terraform.lock.hcl` preserva checksums dos providers. PostgreSQL fixa a família16; a AWS escolhe um minor disponível e gerencia upgrades de minor. `postgres_engine_version_actual` e `redis_engine_version_actual` expõem as versões instaladas. Imagens de aplicação usam tags imutáveis no ECR. As imagens públicas do Dockerfile fixam versão, mas não digest; registre os digests usados no seu deploy para reconstrução bit a bit.

O orçamento é global: C8, r32/s e8 leases compartilhados por sync/async. Escalar workers para4 tarefas não altera esses limites. B mantém uma segunda defesa transacional de concorrência no PostgreSQL. Redis é consultado para admitir; payload HTTP nunca “atravessa Redis”. [ElastiCache: engines suportados](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/engine-versions.html).

## 2. Pré-requisitos e escopo de segurança

Tenha AWS CLI v2 autenticado via SSO/role, Docker com Buildx, Terraform, `jq`, Python3, `curl`, domínio sob seu controle, zona pública Route53 e certificado ACM **ISSUED** na região escolhida cobrindo o hostname. A identidade de provisionamento precisa criar os recursos deste Terraform e passar suas roles; as identidades de runtime têm permissões menores declaradas em `infra/iam.tf`. Confirme quotas Fargate/RDS/ElastiCache e disponibilidade na região. O tutorial usa **us-east-1**; escolha outra região conscientemente por latência, residência e disponibilidade.

```bash
aws sts get-caller-identity
aws --version
terraform version
docker buildx version
jq --version
python3 --version
aws acm list-certificates --region us-east-1 --certificate-statuses ISSUED
aws route53 list-hosted-zones
aws elasticache describe-cache-engine-versions --region us-east-1 \
  --engine redis --engine-version 7.1 --query 'CacheEngineVersions[].EngineVersion'
aws rds describe-db-engine-versions --region us-east-1 --engine postgres \
  --query 'DBEngineVersions[?starts_with(EngineVersion, `16.`)].EngineVersion'
```

ALB termina TLS; A→B e ALB→A usam HTTP apenas em subnets privadas com SG por papel. Redis usa `rediss://`; JDBC usa `sslmode=verify-full` e bundle CA oficial incluído na imagem. Isso não é criptografia ponta a ponta entre todos os serviços. Para produção adicione TLS/mTLS no transporte interno, identidade/autorização de tenant e um ingress adequado. O CIDR restringe o laboratório, não autentica pessoas. `/actuator/*` não é roteado publicamente pelo ALB. As rotas de carga sem proteção e de injeção de falhas estão desligadas na AWS.

RDS gerencia a senha mestre no Secrets Manager. Apenas a execution role lê o segredo necessário para iniciar o container; task roles acessam as filas e telemetria necessárias. A senha Redis é gerada pelo Terraform e entra no state: trate state e planos como segredos. Antes de trabalho em equipe, configure backend remoto criptografado, versionamento, bloqueio e IAM restrito. O backend local é deliberado para tornar o primeiro `validate` independente da sua conta. [Secrets ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data.html), [TLS RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html).

## 3. Configurar e validar antes de criar

Execute a partir da pasta `project`:

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Edite certificate_arn, route53_zone_id, dns_name e allowed_ingress_cidr.
# O CIDR de exemplo203.0.113.10/32 é documental e deve ser substituído.
terraform -chdir=infra init
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate
terraform -chdir=infra plan -out=base.tfplan
```

**Resultado esperado:** validação sem erros e plano dos recursos descritos. Leia o plano, região, tamanhos e identidade AWS. `deploy_apps=false` cria a base e os repositórios, sem serviços ECS ativos. Isso resolve a dependência circular: a imagem precisa de um ECR existente antes que o serviço possa executá-la. A própria base já custa dinheiro, especialmente NAT, ALB, RDS e Redis.

```bash
terraform -chdir=infra apply base.tfplan
terraform -chdir=infra output
```

A criação de RDS/ElastiCache leva minutos. A URL não responderá até as aplicações serem implantadas. Não use `terraform -target` como fluxo normal e não publique estado no Git.

## 4. Build, publicação e deploy

```bash
bash infra/scripts/build-push.sh lab-v1
bash infra/scripts/deploy.sh lab-v1
```

O primeiro script compila `service-a`, `service-b` e `worker` em Docker com Java17/Spring Boot3.5.7, cria imagens Linux/amd64 e publica no ECR da stack. Isso funciona também a partir de Mac ARM com Buildx, sujeito a emulação mais lenta. As tags são imutáveis: para uma correção use `lab-v2`; não sobrescreva `lab-v1`.

O deploy verifica as três imagens, persiste `deploy_apps=true` e a tag em `infra/images.auto.tfvars.json`, gera um plano, pede a palavra APLICAR para executar aquele plano e aguarda serviços estáveis. Preserve esse arquivo nos próximos planos; removê-lo faz o default `deploy_apps=false` propor remover os serviços. Ele não contém senha. Se `services-stable` expirar, leia os eventos ECS antes de repetir o deploy.

**Como verificar:** tarefas RUNNING/healthy, target group de A saudável e logs de inicialização sem erro. B usa Cloud Map `service-b.burstlab.local:8081` (o namespace acompanha `name`). A e workers acessam apenas o primário Redis. As conexões JDBC verificam hostname/cadeia da CA. O bootstrap de schema é serializado pelo backend; é uma simplificação do laboratório, não uma estratégia completa de migrações.

## 5. Validar o caminho completo

```bash
bash infra/scripts/validate.sh
```

O script aguarda ECS, executa uma operação sync, cria um job duas vezes com a mesma chave, exige o mesmo jobId, consulta até SUCCEEDED e falha para FAILED/EXPIRED/RESULT_UNKNOWN. Ele cria dois efeitos de demonstração no banco. Guarde a saída como evidência; um deploy saudável sozinho não prova o fluxo SQS.

Para testar manualmente:

```bash
BASE="$(terraform -chdir=infra output -raw api_url)"
curl -i -H 'Content-Type: application/json' -H 'Idempotency-Key: exemplo-sync-001' \
  -d '{"value":"pedido-001"}' "$BASE/api/sync"
curl -i -H 'Content-Type: application/json' -H 'Idempotency-Key: exemplo-job-001' \
  -d '{"value":"pedido-001"}' "$BASE/api/jobs"
# Copie o jobId da resposta para a consulta:
curl "$BASE/api/jobs/UUID_DA_RESPOSTA"
```

**Esperado:** sync200 quando admitido; 429/Retry-After quando esgotado o orçamento; 503 para dependência indisponível; criação202 com `jobId`/`statusUrl`; consulta com estado durável. 202 é enviado após commit job+outbox, mesmo que SQS esteja momentaneamente indisponível. O dispatcher recupera o envio. Pode publicar duplicado se cair depois do SendMessage; a idempotência é obrigatória. [Outbox AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html).

## 6. Carga, falhas e interpretação

O mesmo script Python de carga aceita URL base: `python3 scripts/load.py --mode sync --url "$BASE" --output results-aws-sync` e `python3 scripts/load.py --mode async --url "$BASE" --output results-aws-async`. Os defaults são chegada20/s, pico120/s por10s. Consulte `--help` para os parâmetros. A comparação das três arquiteturas, incluindo `/api/unprotected`, deve ser executada no ambiente local, onde essa rota de demonstração é habilitada. Na AWS a rota retorna404 por configuração explícita. O simulador HTML não consulta esses serviços e suas métricas nunca são tratadas como execução real.

Para simular queda de worker com uma mensagem em andamento, liste as tasks do serviço e interrompa **uma task específica** com ECS StopTask em ambiente de teste; ECS a repõe. Espere a visibilidade expirar, confirme o mesmo efeito e status final. Não aumente workers para produzir um benchmark artificial: use a mesma chegada, duração, latência, limite e chave única por operação lógica, incluindo toda tentativa real no orçamento. Relate hardware, versões, duração, timeout, erros e percentis observados, sem inventar números.

Long polling é20s, visibilidade inicial45s; o worker limita prefetch/concorrência e estende visibilidade. Sem token ele adia com jitter e não conta uma chamada de B. A fila principal não tem redrive por ReceiveCount: só falha terminal/prazo gera outbox DLQ. Isso evita DLQ causada por esperar capacidade. Long polling não altera o máximo de12h de visibilidade contado do receive original; jobs aqui têm prazo muito menor. [Long polling](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-short-and-long-polling.html), [visibilidade](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/best-practices-processing-messages-timely-manner.html).

## 7. Logs, métricas, traces e escala

```bash
REGION="$(terraform -chdir=infra output -raw region)"
CLUSTER="$(terraform -chdir=infra output -raw cluster_name)"
QUEUE="$(terraform -chdir=infra output -raw queue_url)"
aws logs tail "/burstlab/$CLUSTER/service-a" --region "$REGION" --since 10m
aws logs tail "/burstlab/$CLUSTER/worker" --region "$REGION" --since 10m
aws sqs get-queue-attributes --region "$REGION" --queue-url "$QUEUE" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
aws cloudwatch list-metrics --region "$REGION" --namespace BurstLab
terraform -chdir=infra output dashboard_url
```

O Java agent envia OTLP/gRPC para o ADOT sidecar em localhost4317. O collector exporta traces para X-Ray e faz scrape `/actuator/prometheus` a cada15s, enviando séries selecionadas em formato EMF para CloudWatch. A configuração completa está em `infra/otel-config.yaml.tftpl`. Logs stdout vão pelo driver `awslogs`. A outbox é uma fronteira de contexto: o job persiste o identificador de correlação, mas o exemplo não persiste `traceparent` para ligar o span da aceitação ao futuro dispatcher. Use jobId/correlação para juntar essas etapas; não se promete um único trace contínuo desde o 202. A amostragem de traces é10%; métricas são agregações reais. Não envie tenant/jobId como dimensão irrestrita de CloudWatch, pois cardinalidade aumenta custo. [Configuração ADOT ECS](https://aws-otel.github.io/docs/setup/ecs/config-through-ssm/), [release fixada](https://github.com/aws-observability/aws-otel-collector/releases/tag/v0.43.3).

Escala automática de workers:1–4 tarefas; backlog>64 ou idade>60s por dois períodos adiciona uma tarefa, cooldown60s. Visíveis+invisíveis zero por cinco minutos reduz uma tarefa, cooldown300s. Dados ausentes não equivalem a fila vazia. O teto global Redis continua8 slots/32s⁻¹. O ritmo da escala é mais lento que o burst10s; a fila absorve a diferença. O alarme usa idade SQS aproximada, e a outbox exige observação própria. [Escala ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html).

## 8. Falhas comuns

| Sintoma | Verificação e correção |
| --- | --- |
| `CannotPullContainerError` | Tag existe? build Linux/amd64? NAT/rota/HTTPS e execution role ECR corretos? |
| Tarefa não obtém segredo | Região/ARN, execution role e configuração Secrets; a task role não substitui a execution role |
| `PKIX` ou erro PostgreSQL SSL | Bundle CA presente em `/app/rds-global-bundle.pem`, hostname RDS correto e relógio válido; não desabilite validação |
| 502/target unhealthy | Porta8080, `/actuator/health`, inicialização JDBC e SG ALB→A; observe logs |
| DNS B não resolve | Namespace privado pertence à VPC, serviço B registrado/healthy; DNS pode manter cache por um intervalo |
| Jobs QUEUED sem SQS | Leia outbox, SendMessage/IAM e conectividade; 202 confirma banco, não envio imediato |
| Redis reiniciou | O cliente recupera NOSCRIPT; timeout de aquisição continua ambíguo e usa fail-closed |
| Falha após rotação de segredo | Segredo de ambiente é snapshot do início da task; reinicie A/B/worker para novas credenciais |

## 9. Custos e limitações declaradas

Não há preço estimado fictício. Monte um orçamento para **região escolhida, data da consulta e horas reais de uso** no AWS Pricing Calculator. Os principais termos são: horas vCPU+memória Fargate (5tarefas iniciais com sidecar), NAT por hora e dados, ALB por hora/LCU, IPs públicos, duas instâncias Redis, RDS+armazenamento+backup, chamadas SQS, Secrets Manager, ingestão/retenção CloudWatch, métricas e traces, ECR e transferência entre AZs. Até uma stack ociosa tem custo. Um NAT simplifica o laboratório, mas é dependência de uma AZ e pode cobrar tráfego entre AZs. RDS single-AZ não tem failover Multi-AZ automático.

O state contém segredo Redis; a aplicação usa usuário SQL de bootstrap com privilégios mais amplos que o ideal. O transporte interno HTTP, ausência de autenticação de negócio, inexistência de garantia de fairness e política de retenção ainda a definir impedem tratar este laboratório como produção. A configuração demonstra IAM de runtime específico por serviço; não afirma privilégio mínimo completo no banco. Redis failover pode perder estado do limitador, e nenhum Lua cria transação entre Redis/SQS/B. [Fargate preços](https://aws.amazon.com/fargate/pricing/), [VPC/NAT/IP preços](https://aws.amazon.com/vpc/pricing/), [Calculadora oficial](https://calculator.aws/).

## 10. Limpeza deliberada

Exporte resultados necessários e confirme que aceita excluir jobs/filas/imagens. Use nome de snapshot final único em `terraform.tfvars`; se ele já existir, a destruição de RDS falhará até escolher outro nome.

```bash
bash infra/scripts/cleanup.sh
```

O script mostra o plano de desativação de proteção, pede o nome da stack, aplica essa alteração, apaga imagens apenas nos três ECR da stack e chama `terraform destroy` com sua confirmação normal. RDS gera snapshot final; segredos têm janela de recuperação7dias. Snapshot e backups retidos podem continuar gerando cobrança: revise-os depois, removendo apenas quando o contrato de retenção permitir. A zona Route53/certificado preexistentes não pertencem à stack e permanecem. Não apague state antes de confirmar o término.

## Verificação desta entrega e referências

Executado localmente: Terraform1.13.3 `init -backend=false` com providers assinados fixados, `fmt`, `validate` e `terraform test` com dois planos usando providers mockados (sem chamadas AWS). Build/push, plan/apply reais, tasks, load test AWS e alarmes não foram executados contra uma conta. Validação estática não prova permissões, quotas, disponibilidade regional, DNS/ACM ou comportamento dos serviços gerenciados. O [runbook](operations.md) e as [decisões](decisions.md) aprofundam limites e recuperação.

Fontes oficiais consultadas em **15/10/2026**, linkadas junto às afirmações. As APIs/provedores fixados devem ser atualizados deliberadamente com teste de migração; engine compatível não significa engine idêntico.
