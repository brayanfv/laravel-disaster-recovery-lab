# Gap Analysis — TESTE-DEPLOY

## Objetivo e escopo

Esta análise compara exclusivamente o inventário validado do ambiente `TESTE-DEPLOY` com o cenário-alvo de laboratório para testes futuros de backup e disaster recovery. Não define uma estratégia final de backup ou restore, nem autoriza mudanças no ambiente.

## Estado geral

O ambiente possui a base Laravel/PHP, MySQL, MongoDB, Redis, Docker, Nginx, UFW, Fail2Ban, Cron, Portainer e Git funcional. Um destino externo de backup foi preparado e validado por conectividade, SSH e transferência; os fluxos manuais de backup e restore de MySQL, MongoDB, Redis, Laravel storage e `portainer_data` também foram validados. A automação isolada dos cinco componentes e a execução geral `2026-09-24_142925` foram validadas: `RUN_ID` único, staging remoto único, manifesto global, integridade remota e promoção única. Lock global foi validado em teste real. A retenção de sete restore points foi validada sem remoção no `RUN_ID` `2026-09-24_165238` e com remoção controlada em uma raiz remota isolada. O hardening comum de permissões `600` para artefatos/checksums locais e remotos foi validado. Por fim, o restore point `2026-09-24_173106` foi copiado e validado por SHA-256 em máquina limpa, onde MySQL, MongoDB, Redis, Laravel storage, Portainer, Nginx, PHP-FPM, Laravel, Node 22/Vite, autenticação e Scheduler por Cron foram recuperados e testados. Permanecem gaps reais: uploads públicos sem escopo definido, filas sem carga representativa, HTTPS ausente, gestão formal de secrets, Portainer em `latest`, reprovisionamento do pipeline em novo host e restore automatizado.

A raiz continua com aproximadamente 15,8 GB e foi identificada anteriormente como um limite crítico. Para disponibilizar capacidade ao laboratório, foi criada uma partição ext4 persistente de aproximadamente 30 GB em `/srv/teste-deploy-data`, com cerca de 28 GB livres. Docker e containerd foram migrados e validados após reboot nessa partição, liberando a raiz para os próximos componentes do laboratório. A partição não amplia a raiz nem cria armazenamento externo para backups.

## Matriz de gaps

| Componente | Estado atual | Estado desejado | Gap | Ação futura sugerida | Prioridade |
|---|---|---|---|---|---|
| Host/Sistema Operacional | Linux Mint 22.3, base Ubuntu; raiz com ~15,8 GB; partição local adicional com ~28 GB livres em `/srv/teste-deploy-data` | Linux equivalente com capacidade suficiente para o laboratório | Capacidade local planejada resolvida; Docker/containerd migrados e validados após reboot; a raiz não foi ampliada | Monitorar a capacidade e decidir futuramente quais novos serviços usarão a partição | Resolvida para capacidade do laboratório |
| Laravel/PHP | Laravel 13.27.0, PHP 8.3.6; ambiente `local` e debug habilitado | Aplicação funcional com configuração de laboratório explícita | Ambiente e debug não foram validados como representação do cenário-alvo | Definir futuramente os parâmetros de laboratório a reproduzir | Média |
| Git/versionamento | Repositório funcional em `main`; commit `77bdce8`; `origin` no GitHub; `main` rastreia `origin/main`; working tree limpo | Código e documentação versionáveis em repositório funcional | Resolvido para o laboratório; Git/Bonobo corporativo ainda não foi validado | Validar futuramente o fluxo Git/Bonobo conforme a infraestrutura da empresa | Resolvida para o laboratório |
| Docker e Docker Compose | Docker e containerd ativos após reboot; dados persistentes em `/srv/teste-deploy-data`; stack MongoDB/Redis definida em Compose | Infraestrutura reproduzível por definição declarativa | Portainer foi criado fora de Compose; não há definição versionável para ele; origens antigas estão retidas para rollback | Decidir formato de definição da infraestrutura do Portainer, versões fixas e o momento seguro para encerrar o rollback | Alta |
| MySQL | Backup lógico, script, checksum, transferência, manifesto, lock e retenção validados; o dump foi restaurado em máquina limpa com tabelas esperadas, users=2 e sessions=7108 | Banco reproduzível com dados de laboratório representativos | Backup automatizado e restore manual limpo resolvidos no laboratório; faltam gestão formal de secrets, reprovisionamento do pipeline em novo host e restore automatizado | Formalizar secrets e procedimentos portáveis de backup/restore | Validado no laboratório |
| MongoDB | Backup manual e script automatizado validados; archive/checksum, staging `.incomplete`, promoção e cleanup sem senha em argv; `DR_TEST_MONGO_001` recuperado em máquina limpa | Banco documental persistente e recuperável no laboratório | Backup automatizado e restore manual limpo resolvidos; gestão formal de secrets, monitoramento, decisão do papel em produção e restore automatizado permanecem | Definir o papel de produção e formalizar secrets/restore | Validado no laboratório |
| Redis | Backup manual e script automatizado validados; `SAVE`, parada controlada, archive AOF/RDB, restart, checksum, promoção e permissões `600`; `DR_TEST_REDIS_001` recuperado em máquina limpa | Armazenamento operacional persistente, conforme necessidade do cenário-alvo | Backup automatizado e restore manual limpo resolvidos; decisão do papel em produção, monitoramento e restore automatizado permanecem | Definir o papel real do Redis e a política de produção | Validado no laboratório |
| Nginx | Nginx HTTP ativo na porta 80; rate limits customizados | Proxy web com configuração validada para o laboratório | HTTPS ausente; blocos PHP e aplicação de rate limits ainda pendentes de validação | Decidir se HTTPS integra o laboratório e validar configurações existentes | Média |
| UFW | Ativo; entrada `deny`, libera SSH e HTTP em IPv4/IPv6 | Regras de segurança reproduzíveis e coerentes com serviços | Arquivos efetivos e regra explícita de saída SSH ainda requerem revisão | Validar as regras persistidas e a necessidade da exceção de saída | Média |
| Fail2Ban | Ativo; jail `sshd`; ação `iptables-multiport` | Proteção coerente com serviços expostos | Backend efetivo e filtro Nginx customizado ainda não validados | Validar backend, ação e propósito do filtro Nginx antes de ampliar jails | Média |
| Portainer | Backup manual e script automatizado validados: parada controlada, archive de `portainer_data`, restart, checksums, promoção e restore em máquina limpa com `portainer.db` e login recuperados | Administração reprodutível com versão conhecida | Restore manual limpo foi validado; a tag mutável `portainer/portainer-ce:latest` ainda reduz a reprodutibilidade | Fixar versão ou digest após confirmar a versão de origem | Alta |
| Cron | Serviço ativo (`active (running)`); crontab de `lucas-cooperja` dispara o Laravel Scheduler a cada minuto e inclui o wrapper diário de backup às 02:00; `run-backup-cron.sh` foi validado manualmente e pelo daemon no `RUN_ID` `2026-09-25_160501` | Automação de laboratório explícita e documentada | Execução automática do pipeline, logs, manifesto, promoção e retenção foram validados; Cron tradicional não recupera automaticamente uma execução perdida com host/serviço desligado | Avaliar timer persistente ou estratégia equivalente para execuções perdidas | Validado, com gap operacional |
| Laravel Scheduler | Tarefa `Append the scheduler disaster recovery marker` em `routes/console.php`, validada manualmente, por teste focal e automaticamente pelo Cron; o log foi restaurado e voltou a receber linhas em máquina limpa | Tarefas de teste quando a aplicação exigir automação | Tarefa, recuperação do log e automação Cron do Scheduler resolvidas no laboratório | Manter adaptação de usuário/caminho em futuros hosts | Validado no laboratório |
| Filas, cache e sessão | Todos usam MySQL; tabelas existem; jobs/cache/falhas vazios; sessões têm ~6.604 linhas estimadas | Dados operacionais representativos para teste de perda/recuperação | Fila e cache não possuem carga real; sessões são o único conjunto operacional relevante | Criar futuramente cenários fictícios de fila, cache e sessão | Alta |
| Laravel storage | Backup manual e script automatizado validados; archive relativo, checksum, permissões `600`, promoção e manifesto; `DR_TEST_STORAGE_001.txt` e `scheduler-dr-test.log` foram restaurados no caminho definitivo em máquina limpa | Arquivos persistentes de aplicação e uploads de teste | Storage privado foi validado; uploads públicos, política de ownership em outros hosts, monitoramento e restore automatizado permanecem | Definir escopo de uploads públicos e manter validação de permissões no destino | Validado no laboratório |
| Dados persistentes de aplicação | MySQL, MongoDB, Redis, Portainer, marcador privado Laravel e log do Scheduler foram restaurados e validados em máquina limpa | Conjunto mínimo e seguro de dados representativos | A recuperação dos marcadores foi validada, mas uploads públicos, carga de filas/cache e fluxos de negócio mais representativos ainda não foram exercitados | Definir e gerar dados fictícios adicionais conforme os cenários de recuperação | Alta |
| Secrets/configuração | `.env` existe com permissão `664`; secrets e credenciais identificados por nome | Secrets protegidos e reproduzíveis sem valores em Git | Grupo `nogroup` tem leitura; procedimentos de transporte seguro não foram definidos | Revisar necessidade das permissões e definir tratamento seguro posteriormente | Alta |
| HTTPS/TLS | Nenhum TLS ativo; apenas estrutura Certbot sem certificados emitidos | HTTPS se fizer parte do laboratório-alvo | Ausência de certificado, chave e renovação validada | Decidir se HTTPS deve compor o cenário antes de configurar | Média |
| Armazenamento de backups | Destino externo validado em `teste@172.23.1.115:/srv/backups/teste-deploy`; chave SSH dedicada, SCP, checksums, manifesto, lock e retenção validados; o daemon executou o pipeline completo no `RUN_ID` `2026-09-25_160501`, promovido após manifesto remoto válido e retenção com sucesso | Destino definido, dimensionado e acessível ao laboratório, com automação validada e observável | Pipeline automático via Cron validado; faltam monitoramento ativo/alertas, restore automatizado, uploads públicos e política para execução perdida quando o host estiver desligado | Avaliar recuperação de execução perdida e ampliar observabilidade sem confundir staging local com destino de DR | Validado, com gaps operacionais |
| Reconstrução em segunda máquina | Restore point `2026-09-24_173106` restaurado e validado na máquina limpa `172.23.1.119` | Segunda máquina ou equivalente capaz de reconstruir o ambiente | Reconstrução manual foi validada; faltam restore automatizado e reprovisionamento formal do pipeline de backup no novo host | Transformar o procedimento manual em processo portável e repetir para mudanças relevantes | Validado parcialmente |

## Classificação por natureza

| Natureza | Elementos atuais | Implicação para o laboratório |
|---|---|---|
| Código/versionamento | Código Laravel, configurações sem secrets, migrations, lockfiles e documentação estão no repositório Git funcional do laboratório | Git protege código e configuração versionável, mas não substitui backup de dados persistentes ou secrets. |
| Configuração | Nginx, UFW, Fail2Ban, Cron, MySQL, Laravel e Portainer possuem configurações identificadas | Configurações precisam ser comparadas, reproduzidas e validadas antes de uma reconstrução. |
| Infraestrutura | Host, Docker, Compose, MySQL, MongoDB, Redis, Nginx, UFW, Fail2Ban, Cron e Portainer estão presentes | A definição declarativa/reproduzível do Portainer e demais infraestrutura continua pendente. |
| Dado persistente | MySQL `teste_deploy`, volumes `portainer_data`, `mongodb_data` e `redis_data`, marcador privado e log do Scheduler em `storage/app/private` | O conjunto foi restaurado e validado em máquina limpa; faltam uploads públicos, dados de fila/cache representativos e cenários adicionais de negócio. |
| Secret | `.env`, `APP_KEY`, credenciais de banco/serviços e `/etc/mysql/debian.cnf` | Devem permanecer fora do Git e requerem tratamento protegido para reconstrução. |
| Temporário/reconstruível | `vendor`, `node_modules`, caches, views compiladas, logs, cache/locks de banco | Não devem orientar o teste de persistência; podem ser recriados após reconstrução. |
| Componente de segurança | UFW, Fail2Ban, SSH e Nginx | Estão presentes, mas HTTPS e algumas validações de regras/filtros ainda são gaps. |
| Ferramenta operacional | Docker, Compose, Portainer, Cron e Git | Docker/Portainer/Cron existem; Git está funcional no laboratório; Compose ainda não representa a infraestrutura atual. |

## Prioridades para a próxima fase

1. **Crítica:** definir tratamento de execução perdida quando host/serviço estiver desligado no horário; depois definir monitoramento ativo, alertas e secrets definitivos.
2. **Crítica:** formalizar o reprovisionamento do pipeline de backup em host com outro usuário, caminhos e secrets.
3. **Alta:** definir o papel do Redis, seus requisitos de segurança e a necessidade de backup/restore conforme o cenário de produção.
4. **Alta:** definir o papel de produção do MongoDB/Redis e avaliar o tuning pendente para produção.
5. **Alta:** decidir quais dados e serviços de laboratório usarão `/srv/teste-deploy-data`, além de Docker/containerd, e quando as origens antigas poderão deixar de ser necessárias para rollback.
6. **Alta:** criar dados fictícios adicionais em MySQL, `storage/app/public` quando aplicável, sessões, cache e filas para validar recuperação.
7. **Alta:** substituir a dependência de tag `latest` do Portainer por versão ou digest definido em decisão futura.
8. **Alta:** revisar a necessidade da permissão `664` nos arquivos `.env` e o tratamento seguro de secrets.
9. **Média:** transformar o restore manual validado em runbook portável e, futuramente, em restore automatizado.
10. **Média:** concluir as validações pendentes de Nginx, UFW e Fail2Ban antes de declarar a postura de segurança reproduzível.
11. **Média:** validar futuramente o fluxo Git/Bonobo adotado pela infraestrutura corporativa.

## Itens não necessários no estado atual

- Containers `hello-world` e `ubuntu` parados não possuem mounts ou estado persistente; são recursos descartáveis de teste, sem papel identificado no cenário-alvo.
- S3 está apenas definido como possibilidade de configuração Laravel, sem evidência de uso; sua inclusão depende de decisão posterior.

## Limites desta análise

- Esta Gap Analysis não autoriza instalação, criação de dados, alteração de configuração, criação de jobs, Git, containers, bancos, backups ou restore.
- As ações futuras sugeridas são apenas direcionamentos de planejamento; não constituem estratégia final de backup ou recuperação.
- Os itens classificados como ausentes ou pendentes não estão concluídos.
