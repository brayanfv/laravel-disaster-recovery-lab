# Arquitetura inicial de backup e restore — TESTE-DEPLOY

## Objetivo e limites

Este documento propõe a arquitetura inicial, exclusivamente para o laboratório `TESTE-DEPLOY`, com base no inventário em `docs/inventario/`. Não implementa scripts, dumps, agendamentos de backup, criptografia, cópias externas ou procedimentos de restore.

As frequências, retenções e métodos abaixo são uma **política provisória de laboratório**. Eles precisam ser detalhados, implementados e validados antes de serem usados como procedimento operacional.

## Conceitos

- **Reconstruível:** pode ser recriado a partir de Git, pacote, imagem ou configuração conhecida. Não deve ser a cópia principal de um backup de dados.
- **Persistente:** contém estado ou dados que não podem ser simplesmente recriados e precisa ser preservado ou recuperado por backup.
- **Sensível:** contém secrets, chaves ou credenciais. Exige armazenamento protegido, fora do Git e com criptografia a ser definida.
- **Operacional:** estado necessário ou útil para o funcionamento, mas cuja necessidade de backup depende do papel real que exerce em produção.

## Premissas de armazenamento

`/srv/teste-deploy-data` é uma partição `ext4` local de aproximadamente 30 GB, no mesmo disco físico do sistema. Ela hospeda o data-root do Docker e o root persistente do containerd.

Ela **não é o destino final de disaster recovery** e não protege contra perda física do disco ou do host. Pode ser usada futuramente apenas como:

- área de staging para gerar artefatos;
- área temporária para cópias locais;
- cache local de backup.

O destino final de backup do laboratório foi preparado em uma máquina fisicamente separada da máquina principal. Ele já foi usado e validado nos fluxos manuais dos componentes persistentes; automação de backup, retenção e monitoramento ainda não foram implementados.

## Destino externo validado

| Item | Estado confirmado |
|---|---|
| Máquina principal | `lucas` (`lucas-cooperja`) |
| Máquina externa | `teste-OptiPlex-3070` |
| Endereço atual do laboratório | `172.23.1.115` |
| Usuário de destino | `teste` |
| Diretório de destino | `/srv/backups/teste-deploy` |
| Sistema do destino | Linux Mint 22.3, kernel `6.14.0-37-generic` |
| Filesystem do destino | `ext4` |
| Espaço livre observado | Aproximadamente 33 GB |
| Permissões do diretório pai | `/srv/backups`: `root:root` |
| Permissões do diretório do laboratório | `/srv/backups/teste-deploy`: `teste:teste`, modo `750` |

O IP `172.23.1.115` é o endereço atual do laboratório e poderá exigir nova descoberta ou configuração em outro ambiente.

### Conectividade e escrita

- O teste `ping -c 4 172.23.1.115` recebeu 4 respostas, sem perda de pacotes.
- OpenSSH Server está disponível no destino por socket activation: `ssh.socket` está habilitado e em listening na porta 22 para IPv4 e IPv6. O UFW do destino está inativo neste laboratório.
- A conexão manual `ssh teste@172.23.1.115` foi validada com autenticação por senha.
- Um arquivo marcador não sensível foi enviado por SCP para `/srv/backups/teste-deploy/dr-backup-destination-test.txt` e lido remotamente com sucesso. Esse teste valida rede, SSH, escrita e leitura remota; ele **não é um backup real**.

### Autenticação SSH dedicada ao laboratório

| Item | Estado confirmado |
|---|---|
| Usuário de origem | `lucas-cooperja` |
| Chave privada dedicada | `~/.ssh/id_ed25519_backup_lab` |
| Chave pública dedicada | `~/.ssh/id_ed25519_backup_lab.pub` |
| Finalidade | Autenticação exclusiva para o laboratório de backup/disaster recovery |
| Permissão da chave privada | `600` |
| Permissão da chave pública | `644` |
| Destino | `teste@172.23.1.115:/srv/backups/teste-deploy` |

- A chave pública foi instalada no usuário remoto com `ssh-copy-id`.
- A autenticação sem senha interativa foi validada usando explicitamente a chave dedicada; o comando remoto retornou o marcador `DR_SSH_KEY_TEST`.
- Uma transferência SCP com a opção `-i` apontando para a chave dedicada foi validada, assim como a leitura remota do marcador `DR_SSH_AUTOMATION_TEST`.
- A chave privada não deve entrar no Git, logs ou documentação. Nenhum conteúdo de chave privada ou pública é reproduzido neste documento.
- O endereço `172.23.1.115` continua sendo específico do laboratório atual e poderá mudar em outro ambiente.

## Matriz inicial

| Componente | Tipo de dado | Reconstruível? | Precisa backup? | Método de backup proposto | Método de restore proposto | Frequência inicial | Retenção inicial | Destino | Validação de restore | Observações |
|---|---|---:|---|---|---|---|---|---|---|---|
| Código Laravel, documentação e testes | Código/versionável | Sim, por Git | Não como cópia principal de dados | Versionamento Git e publicação no remoto já inventariado | `git clone` e checkout do commit esperado | A cada mudança/push | Histórico do repositório; fora da retenção de backup de dados | Remoto Git do laboratório | Confirmar commit esperado e arquivos versionados | Git não substitui backup de bancos, storage, secrets ou volumes. |
| `composer.lock`, `package-lock.json` e configurações versionáveis | Configuração versionável | Sim, por Git | Não como cópia de dados principal | Versionamento junto ao código | Checkout do commit esperado | A cada mudança/push | Histórico do repositório | Remoto Git do laboratório | Reinstalar dependências a partir dos lockfiles | Arquivos com secrets não entram nesta categoria. |
| `vendor/` | Dependência PHP | Sim | Não | Não incluir | `composer install` usando o lockfile | N/A | N/A | N/A | Aplicação instala dependências compatíveis | Não versionado. |
| `node_modules/` | Dependência JavaScript | Sim | Não | Não incluir | `npm ci` usando o lockfile | N/A | N/A | N/A | Build/dependências concluídos sem divergência | Não versionado. |
| `.env`, `infra/.env` e secrets de aplicação | Sensível | Não sem os valores protegidos | Sim, em fluxo separado | Artefato de secrets protegido e criptografado; formato e chave ainda pendentes | Recuperar de armazenamento protegido e aplicar permissões adequadas | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado; proteção e automação pendentes | Aplicação conecta aos serviços sem expor valores; `APP_KEY` preservada quando necessária | Nunca incluir no Git, logs ou documentação. |
| `/etc/mysql/debian.cnf` | Configuração sensível do host | Não diretamente | Precisa de decisão | Incluir no fluxo protegido somente se for necessário para manutenção local do MySQL | Restaurar de artefato protegido ou recriar conforme a instalação compatível | Após mudança e/ou diário, se incluído | 7 cópias diárias, provisoriamente | Destino externo validado; proteção e automação pendentes | Administração local do MySQL funciona, se estiver no escopo | Conteúdo não foi inspecionado; não contém dado de negócio da aplicação. |
| MySQL `teste_deploy` | Banco persistente | Não | Sim | Dump lógico manual validado com `mysqldump`, `--single-transaction`, `--routines`, `--triggers`, `--events` e `--no-tablespaces` | Restore manual validado pelo cliente MySQL em banco isolado | Diário | 7 backups diários | Destino externo validado; staging `/srv/teste-deploy-data/backup-staging/mysql` | Tabelas, `users_count = 2` e `sessions_count = 7108` validados no restore isolado | SHA-256 local/remoto e transferência SCP foram validados; automação, nomenclatura e retenção permanecem pendentes. |
| MySQL: sessões, cache, locks e filas | Estado temporário/operacional dentro de `teste_deploy` | Parcialmente | Incluído no dump MySQL; decisão de uso no restore pendente | Coberto pelo dump lógico de `teste_deploy` | Restore como parte do banco | Diário | 7 backups diários | Mesmo destino do MySQL | Confirmar impacto de sessões ativas, cache, jobs pendentes, batches e falhas | Cache e locks são reconstruíveis; sessões encerram ao serem perdidas; filas continuam sem carga real validada. |
| MongoDB e `mongodb_data` | Banco documental persistente | Não | Sim | Archive manual validado com `mongodump` dentro do container, staging `/srv/teste-deploy-data/backup-staging/mongodb` e SHA-256 | `mongorestore` manual validado em banco isolado com remapeamento de namespaces | Diário | 7 backups diários | Destino externo validado | `DR_TEST_MONGO_001` recuperado em `teste_deploy_lab_restore_test.recovery_tests`; contagem 1 | Transferência SCP e checksum local/remoto validados; automação, nomenclatura, retenção e restore em máquina limpa permanecem pendentes. |
| Redis e `redis_data` | Estado operacional persistente | Depende do papel | Sim para o teste; decidir para produção | Backup manual validado do volume após `SAVE` e parada controlada, em `tar.gz` com SHA-256 | Restore manual validado em volume e container Redis isolados com AOF habilitado | Diário, provisoriamente para o laboratório | 7 backups diários | Destino externo validado; staging `/srv/teste-deploy-data/backup-staging/redis` | `DR_TEST_REDIS_001` recuperado com o valor esperado | Em produção, cache descartável pode não requerer backup; filas, sessões ou estado relevante podem requerê-lo. Automação, nomenclatura, retenção e restore em máquina limpa permanecem pendentes. |
| `storage/app/private` | Dados persistentes de aplicação | Não | Sim | Backup manual validado em `tar.gz`, preservando estrutura relativa, com staging `/srv/teste-deploy-data/backup-staging/laravel-storage` e SHA-256 | Extração manual validada em diretório isolado; restore no caminho definitivo permanece para teste em máquina limpa | Diário | 7 backups diários | Destino externo validado | `DR_TEST_STORAGE_001.txt` recuperado com conteúdo correto | O conteúdo é ignorado pelo Git e não é recuperado por clone; automação, nomenclatura, retenção e restore em máquina limpa permanecem pendentes. |
| `scheduler-dr-test.log` | Dado operacional persistente | Não | Avaliar; incluir no teste de laboratório | Incluído no backup manual validado de `storage/app/private` | Extraído e validado junto com o storage privado | Diário | 7 backups diários | Mesmo destino do storage Laravel | Linhas com `DR_TEST_SCHEDULER_001` recuperadas no restore isolado | A retenção real dependerá do papel e da política de logs. |
| Laravel Scheduler | Código e configuração operacional | Sim, exceto arquivos gerados | Não para o código; log é tratado separadamente | Git para `routes/console.php` e teste focal | Checkout do código e validação do Scheduler | A cada mudança/push | Histórico do repositório | Remoto Git do laboratório | `schedule:list` mostra a tarefa; execução gera o marcador | O disparo automático depende da configuração Cron abaixo. |
| Crontab de `lucas-cooperja` | Configuração de usuário | Sim, se exportado/documentado | Sim | Exportar e guardar a configuração do crontab após mudança e/ou diariamente | Reinstalar no usuário correto durante o restore | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado | Confirmar que `schedule:run` executa a cada minuto e que a contagem do marcador aumenta | Inclui o uso temporário de `CACHE_STORE=file`; não há jobs de backup inventariados. |
| Nginx | Pacote e configuração customizada | Pacote: sim; configuração: parcialmente | Sim para configurações customizadas | Preservar/versionar `/etc/nginx/nginx.conf` e o virtual host `teste.local`; não priorizar logs | Reinstalar pacote compatível, restaurar configurações e recriar link simbólico | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado | Nginx responde na aplicação e PHP-FPM é atendido | HTTPS não está configurado; logs não são essenciais ao restore básico. |
| UFW | Software e regras de firewall | Pacote: sim; regras: reproduzíveis/documentáveis | Sim para regras/configuração | Exportar/documentar regras IPv4/IPv6 e preservar arquivos efetivos após validação | Reinstalar UFW e aplicar/reproduzir regras documentadas | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado | Políticas e regras SSH/HTTP IPv4 e IPv6 conferem com o inventário | Não definir comandos de aplicação de regras nesta etapa. |
| Fail2Ban | Software e configuração personalizada | Pacote: sim; configuração: parcialmente | Sim para itens personalizados | Preservar `jail.local` e filtro customizado `filter.d/nginx-req-limit.conf`; demais arquivos de pacote são reconstruíveis | Reinstalar versão compatível e restaurar/reproduzir itens personalizados validados | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado | Jail `sshd`, parâmetros e ação conferem com o inventário | Backend efetivo e filtro Nginx ainda precisam de validação. |
| Docker Engine, containerd, imagens e containers | Infraestrutura operacional | Em grande parte, sim | Não tratar o Docker Root Dir inteiro como backup primário | Reinstalar Docker/containerd compatíveis; baixar imagens e recriar containers/Compose | Recriar serviços por configuração conhecida; restaurar somente volumes necessários | Após mudança de configuração | 7 cópias de configuração, provisoriamente | Destino externo validado | Docker/Compose sobem e recursos esperados ficam visíveis | `/srv/teste-deploy-data/docker` e `/srv/teste-deploy-data/containerd` são estado local, não um backup primário. |
| `portainer_data` | Volume Docker persistente | Não | Sim, por decisão do laboratório | Backup manual validado em `tar.gz` após parada controlada, com staging `/srv/teste-deploy-data/backup-staging/portainer` e SHA-256 | Restore manual validado em volume e container Portainer isolados, com socket Docker e porta publicada separadamente | Diário, provisoriamente | 7 backups diários | Destino externo validado | Login com usuário configurado antes do backup foi recuperado | O container/imagem são reconstruíveis; `portainer/portainer-ce:latest` é um gap técnico por não fixar versão/digest. |
| `mongodb_data` e `redis_data` | Volumes Docker persistentes | Não | Cobertos prioritariamente pelos métodos lógicos dos bancos | Preferir dumps/backup lógico; usar backup de volume somente se for tecnicamente necessário e validado | Restaurar dados lógicos nos serviços recriados | Diário | 7 backups diários | Mesmo destino dos bancos | Marcadores MongoDB e Redis presentes | Não duplicar volume bruto sem avaliar consistência e finalidade. |
| Logs de aplicação, Nginx e MySQL | Logs operacionais | Parcialmente | Não para restore básico; decisão de retenção posterior | Não incluir no escopo inicial de dados críticos | Não aplicável ao restore básico | N/A | N/A | N/A | Aplicação e serviços funcionam sem depender de logs históricos | Exceção: `scheduler-dr-test.log` é marcador operacional do laboratório e foi tratado no storage. |

## Ordem preliminar de restore

Esta sequência é conceitual e deverá ser refinada em um runbook após a definição dos artefatos e da segunda máquina.

1. Preparar sistema operacional/base compatível e a capacidade local necessária.
2. Instalar pacotes essenciais, incluindo PHP/PHP-FPM, MySQL, Nginx, Docker, containerd, UFW e Fail2Ban conforme as versões e dependências validadas.
3. Recuperar o código por Git no commit esperado e reconstruir dependências com os lockfiles.
4. Recriar Docker Compose e os serviços MongoDB/Redis; recriar Portainer conforme sua configuração documentada.
5. Restaurar configurações do host validadas, incluindo MySQL, Nginx, UFW e Fail2Ban.
6. Recuperar secrets e configurações sensíveis por canal protegido, antes de iniciar a aplicação que dependa deles.
7. Restaurar MySQL e MongoDB pelos backups lógicos validados.
8. Restaurar `storage/app/private`, incluindo os marcadores de storage e do Scheduler.
9. Restaurar volumes persistentes necessários, especialmente `portainer_data`; tratar os volumes de bancos conforme o método que vier a ser validado.
10. Ativar e validar Nginx/PHP-FPM e a aplicação.
11. Restaurar o crontab de `lucas-cooperja` e validar o disparo automático do Scheduler.
12. Executar as validações de dados, rede e serviços abaixo.

## Critérios de sucesso do disaster recovery

- A aplicação inicia e é atendida pelo Nginx.
- O repositório Git está no commit esperado para o teste.
- MySQL `teste_deploy` foi recuperado e a aplicação consegue utilizá-lo; o fluxo manual já foi validado em banco isolado e precisa ser repetido em máquina limpa.
- O registro `DR_TEST_MONGO_001` existe após o restore do MongoDB; o fluxo manual isolado já foi validado e precisa ser repetido em máquina limpa.
- O estado `DR_TEST_REDIS_001` existe após o restore do Redis; o fluxo manual isolado já foi validado e precisa ser repetido em máquina limpa quando Redis fizer parte do escopo.
- `storage/app/private/DR_TEST_STORAGE_001.txt` existe após o restore; o fluxo manual isolado já foi validado e precisa ser repetido em máquina limpa.
- A tarefa aparece em `php artisan schedule:list`.
- O Cron volta a disparar o Scheduler automaticamente e novas linhas com `DR_TEST_SCHEDULER_001` aparecem em `storage/app/private/scheduler-dr-test.log`; linhas históricas já foram recuperadas no restore isolado do storage.
- Docker, Compose, MongoDB e Redis iniciam com os recursos esperados.
- Portainer inicia com o volume `portainer_data` preservado; o login com usuário existente no backup já foi validado em restore isolado e precisa ser repetido em máquina limpa.
- As regras essenciais UFW, o jail `sshd` do Fail2Ban e a configuração Nginx conferem com o inventário validado.

## Pendências antes da implementação

- O desenho de automação, organização de staging, nomenclatura por execução, integridade, falhas e retenção provisória está em [backup-automation-design.md](backup-automation-design.md). Ele ainda não implementa scripts ou operações.
- Definir criptografia, gestão de chaves e controle de acesso para secrets.
- Implementar e validar scripts de backup a partir do desenho; não há scripts nesta etapa.
- Definir logs, monitoramento e alertas de falha de backup.
- Definir verificação automática de integridade e validade dos artefatos.
- Implementar retenção por diretório de execução somente após backups válidos e verificados.
- Definir agendamento Cron de backup somente após a validação dos scripts.
- Definir runbook detalhado de restore, incluindo pré-requisitos, ordem e rollback.
- Validar todo o fluxo em uma segunda máquina limpa ou ambiente equivalente.
- Decidir o papel real do Redis em produção e, consequentemente, sua necessidade de backup.
- Definir a versão ou digest do Portainer e decidir o momento seguro para encerrar os dados antigos mantidos para rollback em `/var/lib/docker` e `/var/lib/containerd`.
- Concluir as pendências de configuração de Nginx, UFW e Fail2Ban antes de declarar uma reconstrução de segurança reproduzível.

## Situação atual

Esta é a arquitetura inicial de backup e disaster recovery do laboratório. Os fluxos manuais de backup e restore de MySQL, MongoDB, Redis, Laravel storage e `portainer_data` foram validados com staging local, SHA-256, transferência externa e restores isolados. O desenho da futura automação está documentado, mas ainda não há scripts, agendamento, retenção automática, monitoramento, backup dos demais componentes, criptografia ou restore em máquina limpa.
