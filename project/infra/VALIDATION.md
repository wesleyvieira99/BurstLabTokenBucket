# Validação da infraestrutura — 15/10/2026

Executada localmente com Terraform **1.13.3**, provider AWS **6.44.0** e random **3.7.2**. Os providers foram baixados do registry oficial e verificados por assinatura HashiCorp. Nenhum comando de provisionamento AWS foi executado.

A partir da raiz `project`, os comandos equivalentes são:

```bash
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate -no-color
terraform -chdir=infra test -no-color
for f in infra/scripts/*.sh; do bash -n "$f" || exit; done
```

Nesta sessão, `terraform` foi executado pelo caminho absoluto do binário de trabalho `work/tools/terraform`; a configuração verificada é a mesma pasta `infra` entregue.

| Verificação | Resultado observado |
| --- | --- |
| Inicialização sem backend | Sucesso; lockfile `.terraform.lock.hcl` gerado |
| Formatação recursiva | Sucesso, sem diferenças |
| Validação Terraform | `Success! The configuration is valid.` |
| Planos mockados | `Success! 2 passed, 0 failed.` |
| Bash | Cinco scripts verificados individualmente, sem erro de sintaxe |

Os testes em [tests/config.tftest.hcl](tests/config.tftest.hcl) usam **providers mockados**: verificam a fase base sem aplicações, engine Redis OSS explícito, polling/visibilidade, três serviços privados e limites de escala dos workers. Não usam credenciais, não fazem chamadas AWS e não demonstram comportamento dos serviços gerenciados.

Os scripts verificados são `build-push.sh`, `deploy.sh`, `validate.sh`, `redrive.sh` e `cleanup.sh`, todos em `infra/scripts/`. Verificar sintaxe não executa suas operações AWS.

## Artefatos públicos conferidos

Foram baixados para a pasta de trabalho, sem colocá-los no pacote de entrega:

- [OpenTelemetry Java Agent 2.21.0](https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.21.0/opentelemetry-javaagent.jar): **23.673.491 bytes**; manifesto declara `Implementation-Version: 2.21.0`; SHA-256 `5b35ccc6c275fd477a06db01923813e13d99c1a52a20b0ea8ed6576eae177c7d`.
- [Bundle CA global RDS](https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem): **174.560 bytes**, **114 certificados**; SHA-256 observado `90a6f1a7978a1b1b096dca6c57511ca48d3b8cf052f8e704baf358f34ea2f21b`. O bundle é atualizado pela AWS; esse hash registra a consulta, não é uma exigência de imutabilidade futura.

## Não executado

Não foram executados Docker build/push, plano real com credenciais AWS, `apply`, deploy ECS, smoke test AWS, carga AWS, failover gerenciado ou entrega de alarmes. Docker não estava disponível para validar containers. DNS, ACM, IAM efetivo, quotas, disponibilidade regional, runtime do collector e custos precisam ser verificados pelo leitor ao implantar. Os comandos e resultados esperados estão em [../docs/aws.md](../docs/aws.md).
