# Gap Analysis — TESTE-DEPLOY

## Objetivo e escopo

Esta análise compara exclusivamente o inventário validado do ambiente `TESTE-DEPLOY` com o cenário-alvo de laboratório para testes futuros de backup e disaster recovery. Não define uma estratégia final de backup ou restore, nem autoriza mudanças no ambiente.

## Estado geral

O ambiente possui a base Laravel/PHP, MySQL, MongoDB, Redis, Docker, Nginx, UFW, Fail2Ban, Cron, Portainer e Git funcional. Um destino externo de backup foi preparado e validado por conectividade, SSH e transferência de um arquivo marcador. Contudo, ainda não tem todos os componentes e dados necessários para exercitar uma recuperação completa e representativa: não há dados persistentes de uploads; as filas não têm trabalho real; HTTPS não está configurado; e backups reais ainda não foram implementados.

A raiz continua com aproximadamente 15,8 GB e foi identificada anteriormente como um limite crítico. Para disponibilizar capacidade ao laboratório, foi criada uma partição ext4 persistente de aproximadamente 30 GB em `/srv/teste-deploy-data`, com cerca de 28 GB livres. Docker e containerd foram migrados e validados após reboot nessa partição, liberando a raiz para os próximos componentes do laboratório. A partição não amplia a raiz nem cria armazenamento externo para backups.

## Matriz de gaps

| Componente | Estado atual | Estado desejado | Gap | Ação futura sugerida | Prioridade |
|---|---|---|---|---|---|
| Host/Sistema Operacional | Linux Mint 22.3, base Ubuntu; raiz com ~15,8 GB; partição local adicional com ~28 GB livres em `/srv/teste-deploy-data` | Linux equivalente com capacidade suficiente para o laboratório | Capacidade local planejada resolvida; Docker/containerd migrados e validados após reboot; a raiz não foi ampliada | Monitorar a capacidade e decidir futuramente quais novos serviços usarão a partição | Resolvida para capacidade do laboratório |
| Laravel/PHP | Laravel 13.27.0, PHP 8.3.6; ambiente `local` e debug habilitado | Aplicação funcional com configuração de laboratório explícita | Ambiente e debug não foram validados como representação do cenário-alvo | Definir futuramente os parâmetros de laboratório a reproduzir | Média |
| Git/versionamento | Repositório funcional em `main`; commit `77bdce8`; `origin` no GitHub; `main` rastreia `origin/main`; working tree limpo | Código e documentação versionáveis em repositório funcional | Resolvido para o laboratório; Git/Bonobo corporativo ainda não foi validado | Validar futuramente o fluxo Git/Bonobo conforme a infraestrutura da empresa | Resolvida para o laboratório |
| Docker e Docker Compose | Docker e containerd ativos após reboot; dados persistentes em `/srv/teste-deploy-data`; stack MongoDB/Redis definida em Compose | Infraestrutura reproduzível por definição declarativa | Portainer foi criado fora de Compose; não há definição versionável para ele; origens antigas estão retidas para rollback | Decidir formato de definição da infraestrutura do Portainer, versões fixas e o momento seguro para encerrar o rollback | Alta |
| MySQL | MySQL ativo, banco `teste_deploy`, tabelas Laravel presentes | Banco reproduzível com dados de laboratório representativos | Dados de negócio mínimos; medição física do datadir ainda pendente | Criar futuramente dados fictícios e medir armazenamento antes do teste | Alta |
| MongoDB | Instalado via Docker Compose; MongoDB 8.0.32; volume `mongodb_data` no data-root Docker; persistência após restart validada | Banco documental persistente e recuperável no laboratório | Backup/restore não implementados; tuning de produção e restore em máquina limpa não validados | Definir futuramente backup/restore, validar recuperação limpa e avaliar tuning | Alta |
| Redis | Instalado via Docker Compose; AOF e volume `redis_data` validados após restart; Laravel continua usando `database` para cache, sessão e fila | Armazenamento operacional persistente, conforme necessidade do cenário-alvo | Integração Laravel não existe; backup/restore e restore em máquina limpa não foram definidos; necessidade de backup depende do papel em produção | Definir futuramente o papel do Redis, segurança e a necessidade de backup/restore | Alta |
| Nginx | Nginx HTTP ativo na porta 80; rate limits customizados | Proxy web com configuração validada para o laboratório | HTTPS ausente; blocos PHP e aplicação de rate limits ainda pendentes de validação | Decidir se HTTPS integra o laboratório e validar configurações existentes | Média |
| UFW | Ativo; entrada `deny`, libera SSH e HTTP em IPv4/IPv6 | Regras de segurança reproduzíveis e coerentes com serviços | Arquivos efetivos e regra explícita de saída SSH ainda requerem revisão | Validar as regras persistidas e a necessidade da exceção de saída | Média |
| Fail2Ban | Ativo; jail `sshd`; ação `iptables-multiport` | Proteção coerente com serviços expostos | Backend efetivo e filtro Nginx customizado ainda não validados | Validar backend, ação e propósito do filtro Nginx antes de ampliar jails | Média |
| Portainer | Em execução; volume persistente; imagem `portainer/portainer-ce:latest` | Administração reprodutível com versão conhecida | Uso de tag mutável `latest`; dados persistentes ainda não classificados internamente | Fixar versão/digest por decisão futura e validar dados do volume | Alta |
| Cron | Serviço ativo; crontab de `lucas-cooperja` dispara o Laravel Scheduler a cada minuto; tarefas de pacote e Sendmail local | Automação de laboratório explícita e documentada | Gap de integração Cron + Scheduler resolvido; não há jobs de backup | Manter a configuração documentada e definir backup em etapa própria | Resolvida para Scheduler |
| Laravel Scheduler | Tarefa `Append the scheduler disaster recovery marker` em `routes/console.php`, validada manualmente, por teste focal e automaticamente pelo Cron; gera log privado persistente | Tarefas de teste quando a aplicação exigir automação | Gaps de tarefa representativa e automação resolvidos; restore em máquina limpa permanece pendente | Validar recuperação em máquina limpa | Resolvida para automação |
| Filas, cache e sessão | Todos usam MySQL; tabelas existem; jobs/cache/falhas vazios; sessões têm ~6.604 linhas estimadas | Dados operacionais representativos para teste de perda/recuperação | Fila e cache não possuem carga real; sessões são o único conjunto operacional relevante | Criar futuramente cenários fictícios de fila, cache e sessão | Alta |
| Laravel storage | Marcador privado `storage/app/private/DR_TEST_STORAGE_001.txt` (155 bytes), ignorado pelo Git; `public/storage` ausente | Arquivos persistentes de aplicação e uploads de teste | Gap de ausência de marcador privado resolvido; backup/restore e fluxo público ainda não foram validados | Validar futuramente backup/restore em máquina limpa e criar dados públicos somente se forem necessários | Resolvido para marcador privado |
| Dados persistentes de aplicação | MySQL contém usuários, migrations e sessões; volumes Portainer, MongoDB e Redis; marcador privado Laravel e log do Scheduler | Conjunto mínimo e seguro de dados representativos | Há marcadores de storage, mas recuperação completa de arquivos e fluxos de negócio ainda não foi testada | Definir e gerar dados fictícios adicionais conforme os cenários de recuperação | Alta |
| Secrets/configuração | `.env` existe com permissão `664`; secrets e credenciais identificados por nome | Secrets protegidos e reproduzíveis sem valores em Git | Grupo `nogroup` tem leitura; procedimentos de transporte seguro não foram definidos | Revisar necessidade das permissões e definir tratamento seguro posteriormente | Alta |
| HTTPS/TLS | Nenhum TLS ativo; apenas estrutura Certbot sem certificados emitidos | HTTPS se fizer parte do laboratório-alvo | Ausência de certificado, chave e renovação validada | Decidir se HTTPS deve compor o cenário antes de configurar | Média |
| Armazenamento de backups | Destino externo validado em `teste@172.23.1.115:/srv/backups/teste-deploy`; ext4 com ~33 GB livres observados; escrita/leitura por SCP/SSH validadas | Destino definido, dimensionado e acessível ao laboratório | Ausência de destino externo resolvida; autenticação automatizada, retenção, formatos, checksums e backups reais permanecem pendentes | Definir chaves SSH, automação, integridade e política operacional antes de gerar backups reais | Resolvida para destino |
| Reconstrução em segunda máquina | Não identificada | Segunda máquina ou equivalente capaz de reconstruir o ambiente | Não há destino, automação declarativa ou teste de reconstrução | Definir futuramente a máquina-alvo e o critério de sucesso do teste | Crítica |

## Classificação por natureza

| Natureza | Elementos atuais | Implicação para o laboratório |
|---|---|---|
| Código/versionamento | Código Laravel, configurações sem secrets, migrations, lockfiles e documentação estão no repositório Git funcional do laboratório | Git protege código e configuração versionável, mas não substitui backup de dados persistentes ou secrets. |
| Configuração | Nginx, UFW, Fail2Ban, Cron, MySQL, Laravel e Portainer possuem configurações identificadas | Configurações precisam ser comparadas, reproduzidas e validadas antes de uma reconstrução. |
| Infraestrutura | Host, Docker, Compose, MySQL, MongoDB, Redis, Nginx, UFW, Fail2Ban, Cron e Portainer estão presentes | A definição declarativa/reproduzível do Portainer e demais infraestrutura continua pendente. |
| Dado persistente | MySQL `teste_deploy`, volumes `portainer_data`, `mongodb_data` e `redis_data`, marcador privado e log do Scheduler em `storage/app/private` | Há persistência validada no MongoDB e Redis, mas faltam decisões de backup/restore, dados fictícios de aplicação e uploads. |
| Secret | `.env`, `APP_KEY`, credenciais de banco/serviços e `/etc/mysql/debian.cnf` | Devem permanecer fora do Git e requerem tratamento protegido para reconstrução. |
| Temporário/reconstruível | `vendor`, `node_modules`, caches, views compiladas, logs, cache/locks de banco | Não devem orientar o teste de persistência; podem ser recriados após reconstrução. |
| Componente de segurança | UFW, Fail2Ban, SSH e Nginx | Estão presentes, mas HTTPS e algumas validações de regras/filtros ainda são gaps. |
| Ferramenta operacional | Docker, Compose, Portainer, Cron e Git | Docker/Portainer/Cron existem; Git está funcional no laboratório; Compose ainda não representa a infraestrutura atual. |

## Prioridades para a próxima fase

1. **Crítica:** definir autenticação automatizada por chave SSH, formatos, checksums e automação antes de gerar backups reais no destino externo validado.
2. **Crítica:** definir o destino e os critérios para uma futura reconstrução em segunda máquina.
3. **Alta:** definir o papel do Redis, seus requisitos de segurança e a necessidade de backup/restore conforme o cenário de produção.
4. **Alta:** definir backup/restore do MongoDB, validar recuperação em máquina limpa e avaliar o tuning pendente para produção.
5. **Alta:** decidir quais dados e serviços de laboratório usarão `/srv/teste-deploy-data`, além de Docker/containerd, e quando as origens antigas poderão deixar de ser necessárias para rollback.
6. **Alta:** criar dados fictícios adicionais em MySQL, `storage/app/public` quando aplicável, sessões, cache e filas para validar recuperação.
7. **Alta:** substituir a dependência de tag `latest` do Portainer por versão ou digest definido em decisão futura.
8. **Alta:** revisar a necessidade da permissão `664` nos arquivos `.env` e o tratamento seguro de secrets.
9. **Média:** validar a recuperação em máquina limpa, incluindo a configuração Cron + Scheduler, quando a estratégia de restore for definida.
10. **Média:** concluir as validações pendentes de Nginx, UFW e Fail2Ban antes de declarar a postura de segurança reproduzível.
11. **Média:** validar futuramente o fluxo Git/Bonobo adotado pela infraestrutura corporativa.

## Itens não necessários no estado atual

- Containers `hello-world` e `ubuntu` parados não possuem mounts ou estado persistente; são recursos descartáveis de teste, sem papel identificado no cenário-alvo.
- S3 está apenas definido como possibilidade de configuração Laravel, sem evidência de uso; sua inclusão depende de decisão posterior.

## Limites desta análise

- Esta Gap Analysis não autoriza instalação, criação de dados, alteração de configuração, criação de jobs, Git, containers, bancos, backups ou restore.
- As ações futuras sugeridas são apenas direcionamentos de planejamento; não constituem estratégia final de backup ou recuperação.
- Os itens classificados como ausentes ou pendentes não estão concluídos.
