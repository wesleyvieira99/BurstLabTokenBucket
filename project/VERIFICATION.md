# Evidências de verificação — 15/10/2026

## Executado de fato

Ambiente macOS arm64, OpenJDK **17.0.18**, Maven instalado. Dependências públicas baixadas para cache isolado `work/m2`. Nenhum provisionamento AWS.

- **Maven reactor completo: BUILD SUCCESS** nos módulos common, service-a, service-b, worker. JARs executáveis gerados.
- **15 testes, zero falhas, zero erros, zero pulados na execução final:** 11 integração Lua/Lettuce contra **Redis real7.2.7** compilado do tarball oficial; 1 validação de payload; 3 testes unitários worker (Mockito). Redis não foi substituído por mock nos testes do limitador.
- Redis: cheio/vazio, não devolver token, reposição parcial/teto, custo inválido/impossível, configuração inválida/drift, TTL após reposição, duas instâncias competindo pelo mesmo orçamento, recuperação NOSCRIPT, corrida intencional read/modify/write, retrocesso de relógio preservando TTL/retry e leases futuras.
- Worker unitário: queda após terceira tentativa confirma resultado durável antes de falhar; ausência de resultado preserva RESULT_UNKNOWN; espera de capacidade não consome tentativa nem envia à DLQ. Estes três testes **não validam transporte SQS real**.
- **HTTP nativo real com duas réplicas A + B + Redis + PostgreSQL16.13 temporário:** sync200; duplicata retorna resultado idempotente; mesma chave/payload diferente409; rajada simultânea de64 chamadas sobre duas réplicas A produziu **8 respostas200 +56 respostas429**; async202 persistiu job/outbox; chave repetida retorna mesmojob, payload divergente409; B1800ms produziu504.
- **Duas réplicas B reais contra o mesmo PostgreSQL:** 32 chamadas HTTP simultâneas diretas, 8 respostas200 e24 respostas503. Demonstra compartilhamento dos8 slots transacionais independentemente do Redis. Consulta SQL confirmou1 job e1 evento outbox pendente da aceitação comSQS desativado. Registro: [verification/b-global.txt](verification/b-global.txt).
- `docker compose config --quiet`: configuração Compose válida.
- `python3 -m py_compile scripts/*.py`: sintaxe Python válida.
- Cinco POMs XML parseados; Java compilado, imports/dependências resolvidos.
- Terraform: evidências em [infra/VALIDATION.md](infra/VALIDATION.md): fmt/validate, dois testes com mocks e sintaxe Bash, sem provisionamento AWS.

Os registros curtos estão em [verification/maven-summary.txt](verification/maven-summary.txt) e [verification/native-smoke.txt](verification/native-smoke.txt). As contagens HTTP são **um smoke de concorrência**, não um benchmark ou uma previsão de produção.

Comando Maven final executado no ambiente de criação (caminho do cache adaptado):

```sh
REDIS_TEST_URI=redis://localhost:16379 mvn -B -ntp \
  -f outputs/burstlab/project/pom.xml -Dmaven.repo.local="$PWD/work/m2" verify
```

Comando HTTP executado:

```sh
python3 scripts/smoke.py --url http://localhost:18080 \
  --b-url http://localhost:18081 --second-url http://localhost:18082 --outbox-only
```

Os processos de teste usaram portas isoladas e PostgreSQL temporário sob `work/`. O `--outbox-only` é deliberado: SQS estava desativado nesta prova; a prova confirma aceitação transacional, **não** conclusão assíncrona.

## Não executado / limitações

- Docker Engine não respondeu, mesmo após iniciar Docker Desktop. O primeiro Maven verify pulou integração Redis; depois o Redis nativo permitiu executar todos os testes reais. A execução final não contém skips.
- **Não executado:** `docker compose up --build`, imagens Docker, LocalStack/SQS end-to-end, `scripts/failures.py` completo, teste real de kill após commit B antes de DeleteMessage, extensão de visibilidade, drenagem real SQS, `scripts/load.py --mode all`, AWS deploy/TLS/CloudWatch/IAM em conta real. Scripts e infraestrutura estão entregues para esses ensaios; não há números de benchmark inventados.
- LocalStack é emulação de desenvolvimento, não comprovação de durabilidade AWS. PostgreSQL local em volume persiste jobs/outbox. Evite recriar LocalStack com jobs ativos; uma fila local recriada perde mensagens já publicadas. Investigue/reconcilie jobs antes de apagar o emulador.
- Deadline propagado usa epoch e depende de sincronização de relógios; pausas JVM não têm prazo de tempo real. Conexões/threads/pools são limitados, mas dimensionamento RDS total depende de réplicas.
- Leases Redis podem expirar durante pausa longa; o guard transacional PostgreSQL dentro de B é a última defesa. Failover Redis pode perder estado e conceder burst adicional; precisão de taxa não é uma garantia linearizável através de failover.
- Exemplo sem autenticação de usuário/tenant, sem fairness por tenant e sem reserva sync/async; estes trade-offs estão documentados. O ambiente AWS restringe ingresso por CIDR, mas uma API pública requer autorização de aplicação.
- A tabela de efeitos representa o efeito demonstrativo. Um efeito externo precisa de idempotência no destino; o exemplo não promete exactly-once de rede.
- Versões foram fixadas para reprodução; não são uma certificação de segurança de produção. Imagens e dependências devem passar atualização de patches e scan antes de promoção.
