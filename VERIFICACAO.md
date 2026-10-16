# BurstLab — verificação da entrega

Data: 15/10/2026. Os resultados abaixo descrevem execuções reais neste ambiente, sem provisionar AWS.

## Portal

- Sintaxe JavaScript verificada com `node --check`.
- **9 testes do simulador passaram**, usando `node --test portal/tests/simulator.test.cjs`: tráfego normal; envelope de admissões/concorrência; burst e drenagem assíncrona; Redis indisponível; duplicata e worker interrompido; sobrecarga e retries; degradação/recuperação; prazo/DLQ; determinismo e saldo limitado.
- Interface aberta em navegador real e inspecionada em viewports de 1440×1000, 768×1024 e 390×844. Ajustes feitos após detectar overflow no tablet e interceptação de clique no diagrama. Nos tamanhos conferidos, a largura de conteúdo corresponde à viewport.
- Busca por `outbox` retornou capítulos com o termo. A busca normaliza acentos e caixa.
- Botão Copiar conferido contra o clipboard; conteúdo correspondeu ao código.
- Progresso de capítulo marcado, recarregado e confirmado; restaurado para zero após o teste.
- Temas claro e escuro conferidos; preferência persiste localmente.
- Token visual: 8 débitos, nona aquisição negada; avançar31,25ms repôs1 token.
- Simulador: iniciar, pausar, reiniciar, passo, burst, alternância de modos, Redis fora, duplicata, queda de worker e degradação de B conferidos. Com Redis fora no modo assíncrono,10 passos acumularam10 trabalhos e0 admissões.
- Calculadora: com saída igual à entrada, exibiu `Não drena`.
- Diagrama síncrono/assíncrono e detalhes clicáveis conferidos; o worker aparece na arquitetura assíncrona.
- Explorador carregou arquivos reais do pacote por HTTP. Pacote ZIP gerado dos mesmos fontes; nenhum download fictício.
- Menu móvel, fechamento e rotas conferidos. Campos possuem rótulos, diálogos têm títulos, botões de ícone têm nomes, navegação fechada fica inerte em telas menores, gráficos têm descrição textual, foco visível e link de salto. CSS respeita `prefers-reduced-motion` e oferece fallback para vidro sem `backdrop-filter`.
- Nenhum erro JavaScript observado no console durante os cenários conferidos.

Esta inspeção não é uma auditoria formal WCAG e não cobre todos os leitores de tela ou navegadores. A animação SMIL fica oculta com movimento reduzido; não foi executada uma matriz automatizada de tecnologias assistivas.

## Java e Redis

- Maven reactor dos quatro módulos: **BUILD SUCCESS**, JARs executáveis gerados.
- **15 testes passaram sem skips:**11 contra Redis real7.2.7,1 de payload e3 do worker com Mockito.
- HTTP real com duas instâncias A: rajada simultânea de64 chamadas resultou em8 respostas200 e56 rejeições429.
- HTTP real com duas instâncias B usando o mesmo PostgreSQL:32 chamadas resultaram em8 respostas200 e24 respostas503; demonstra o guard global dentro de B.
- Idempotência, conflito de payload409, aceite202 com job/outbox persistido, consulta de estado e timeout de B conferidos nativamente.
- Compose validado estruturalmente; scripts Python tiveram sintaxe verificada.

Condições, comandos e registros: `project/VERIFICATION.md` e `project/verification/`. Contagens de smoke não são benchmarks nem certificação de capacidade.

## Terraform

- Terraform1.13.3: `fmt -check` e `validate` passaram.
- Dois testes de planos com providers mockados passaram.
- Cinco scripts Bash passaram em `bash -n`.
- URLs oficiais do Java Agent OpenTelemetry2.21.0 e da CA RDS foram baixadas/verificadas.

Ver `project/infra/VALIDATION.md` e `project/docs/aws.md`.

## Não executado

O Docker Engine não ficou disponível. Por isso, **não foram executados o build das imagens, o Compose completo, LocalStack/SQS ponta a ponta, o teste real de queda após commit antes do DeleteMessage, a extensão de visibilidade nem o comparativo de carga completo**. Esses testes e scripts estão entregues para reprodução com Docker ativo.

**Nenhum recurso pago foi provisionado na AWS.** TLS, IAM, deploy ECS, autoscaling e CloudWatch em conta real ainda exigem validação no ambiente do usuário. Os testes de Terraform com mocks validam a configuração e as invariantes locais, não o comportamento dos serviços gerenciados.

O simulador é explicitamente didático e não apresenta suas contagens como métricas reais. Limitações de clocks, failover, leases, retenção/idempotência, autenticação, fairness, custos e transporte estão documentadas no portal e nos guias.
