# Arquitetura inicial de backup e restore — TESTE-DEPLOY

## Objetivo e limites

Este documento registra a arquitetura do laboratório `TESTE-DEPLOY`, com base no inventário em `docs/inventario/`. A proposta inicial evoluiu para scripts de componente, orquestrador, checksums, promoção remota, lock, retenção e wrapper de Cron já implementados e validados conforme os documentos específicos.

As frequências e retenções permanecem uma **política provisória de laboratório**. O restore continua majoritariamente manual, e a gestão formal de secrets, a reprodutibilidade entre hosts e os demais limites descritos ao final ainda precisam de definição antes de uso em produção.

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

O destino final de backup do laboratório foi preparado em uma máquina fisicamente separada da máquina principal. Ele é o destino de DR do laboratório; os fluxos automatizados dos cinco componentes, o manifesto global, a promoção remota, o lock e a retenção já foram implementados e validados. O staging local não substitui esse destino externo.

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
| MySQL `teste_deploy` | Banco persistente | Não | Sim | `backup-mysql.sh` executa dump lógico com `--single-transaction`, `--routines`, `--triggers`, `--events` e `--no-tablespaces`; integrado ao orquestrador | Restore manual validado em máquina limpa pelo cliente MySQL | Diário | 7 restore points completos, política provisória | Destino externo promovido, com manifesto | Tabelas restauradas; `users_count = 2` e `sessions_count = 7108` no restore point validado | Backup, checksum, transferência, retenção e restore manual limpo validados; secrets e restore automatizado continuam pendentes. |
| MySQL: sessões, cache, locks e filas | Estado temporário/operacional dentro de `teste_deploy` | Parcialmente | Incluído no dump MySQL; decisão de uso no restore pendente | Coberto pelo dump lógico de `teste_deploy` | Restore como parte do banco | Diário | 7 backups diários | Mesmo destino do MySQL | Confirmar impacto de sessões ativas, cache, jobs pendentes, batches e falhas | Cache e locks são reconstruíveis; sessões encerram ao serem perdidas; filas continuam sem carga real validada. |
| MongoDB e `mongodb_data` | Banco documental persistente | Não | Sim | `backup-mongodb.sh` cria archive lógico com `mongodump`, checksum e transferência; integrado ao orquestrador | `mongorestore --drop` manual validado em máquina limpa | Diário | 7 restore points completos, política provisória | Destino externo promovido, com manifesto | `DR_TEST_MONGO_001` recuperado pelo campo `identificador`; um documento, zero falhas | Backup automatizado e restore manual limpo validados; gestão formal de secrets e restore automatizado continuam pendentes. |
| Redis e `redis_data` | Estado operacional persistente | Depende do papel | Sim para o teste; decidir para produção | `backup-redis.sh` executa `SAVE`, parada controlada e archive do volume; integrado ao orquestrador | Restore manual validado em máquina limpa em `redis_data` com AOF | Diário, provisoriamente para o laboratório | 7 restore points completos, política provisória | Destino externo promovido, com manifesto | `DR_TEST_REDIS_001` retornou o valor esperado após restart | Em produção, cache descartável pode não requerer backup; decisão do papel real continua pendente. |
| `storage/app/private` | Dados persistentes de aplicação | Não | Sim | `backup-laravel-storage.sh` cria archive relativo, checksum e transferência; integrado ao orquestrador | Extração manual validada no caminho definitivo em máquina limpa | Diário | 7 restore points completos, política provisória | Destino externo promovido, com manifesto | `DR_TEST_STORAGE_001.txt` e `scheduler-dr-test.log` recuperados | O conteúdo é ignorado pelo Git; uploads públicos ainda não fazem parte do escopo validado. |
| `scheduler-dr-test.log` | Dado operacional persistente | Não | Avaliar; incluir no teste de laboratório | Incluído no backup manual validado de `storage/app/private` | Extraído e validado junto com o storage privado | Diário | 7 backups diários | Mesmo destino do storage Laravel | Linhas com `DR_TEST_SCHEDULER_001` recuperadas no restore isolado | A retenção real dependerá do papel e da política de logs. |
| Laravel Scheduler | Código e configuração operacional | Sim, exceto arquivos gerados | Não para o código; log é tratado separadamente | Git para `routes/console.php` e teste focal | Checkout do código e validação do Scheduler | A cada mudança/push | Histórico do repositório | Remoto Git do laboratório | `schedule:list` mostra a tarefa; execução gera o marcador | O disparo automático depende da configuração Cron abaixo. |
| Crontab do usuário da aplicação | Configuração de usuário | Sim, se documentado/adaptado | Sim | Documentar e reprovisionar para o usuário e caminho do host alvo | Reinstalar no usuário correto durante o restore | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado | `schedule:run` executou automaticamente e aumentou o marcador no host limpo | A entrada do Scheduler foi validada em máquina limpa; o Cron de backup não deve ser copiado sem reprovisionar dependências de host. |
| Nginx | Pacote e configuração customizada | Pacote: sim; configuração: parcialmente | Sim para configurações customizadas | Preservar/versionar `/etc/nginx/nginx.conf` e o virtual host `teste.local`; não priorizar logs | Reinstalar pacote compatível, restaurar configurações e recriar link simbólico | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado | Nginx responde na aplicação e PHP-FPM é atendido | HTTPS não está configurado; logs não são essenciais ao restore básico. |
| UFW | Software e regras de firewall | Pacote: sim; regras: reproduzíveis/documentáveis | Sim para regras/configuração | Exportar/documentar regras IPv4/IPv6 e preservar arquivos efetivos após validação | Reinstalar UFW e aplicar/reproduzir regras documentadas | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado | Políticas e regras SSH/HTTP IPv4 e IPv6 conferem com o inventário | Não definir comandos de aplicação de regras nesta etapa. |
| Fail2Ban | Software e configuração personalizada | Pacote: sim; configuração: parcialmente | Sim para itens personalizados | Preservar `jail.local` e filtro customizado `filter.d/nginx-req-limit.conf`; demais arquivos de pacote são reconstruíveis | Reinstalar versão compatível e restaurar/reproduzir itens personalizados validados | Após mudança e diário | 7 cópias diárias, provisoriamente | Destino externo validado | Jail `sshd`, parâmetros e ação conferem com o inventário | Backend efetivo e filtro Nginx ainda precisam de validação. |
| Docker Engine, containerd, imagens e containers | Infraestrutura operacional | Em grande parte, sim | Não tratar o Docker Root Dir inteiro como backup primário | Reinstalar Docker/containerd compatíveis; baixar imagens e recriar containers/Compose | Recriar serviços por configuração conhecida; restaurar somente volumes necessários | Após mudança de configuração | 7 cópias de configuração, provisoriamente | Destino externo validado | Docker/Compose sobem e recursos esperados ficam visíveis | `/srv/teste-deploy-data/docker` e `/srv/teste-deploy-data/containerd` são estado local, não um backup primário. |
| `portainer_data` | Volume Docker persistente | Não | Sim, por decisão do laboratório | `backup-portainer.sh` cria archive após parada controlada; integrado ao orquestrador | Restore manual validado em máquina limpa, com `portainer.db` e login recuperados | Diário, provisoriamente | 7 restore points completos, política provisória | Destino externo promovido, com manifesto | Login com usuário existente antes do backup foi recuperado | O container/imagem são reconstruíveis; `portainer/portainer-ce:latest` continua gap técnico por não fixar versão/digest. |
| `mongodb_data` e `redis_data` | Volumes Docker persistentes | Não | Cobertos prioritariamente pelos métodos lógicos dos bancos | Preferir dumps/backup lógico; usar backup de volume somente se for tecnicamente necessário e validado | Restaurar dados lógicos nos serviços recriados | Diário | 7 backups diários | Mesmo destino dos bancos | Marcadores MongoDB e Redis presentes | Não duplicar volume bruto sem avaliar consistência e finalidade. |
| Logs de aplicação, Nginx e MySQL | Logs operacionais | Parcialmente | Não para restore básico; decisão de retenção posterior | Não incluir no escopo inicial de dados críticos | Não aplicável ao restore básico | N/A | N/A | N/A | Aplicação e serviços funcionam sem depender de logs históricos | Exceção: `scheduler-dr-test.log` é marcador operacional do laboratório e foi tratado no storage. |

## Ordem de restore validada no laboratório

Esta sequência foi exercitada manualmente no host limpo. Ela permanece um runbook de laboratório e deve ser adaptada aos caminhos, usuários, segredos e versões do host alvo.

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
11. Restaurar o crontab do usuário local correto e validar o disparo automático do Scheduler.
12. Executar as validações de dados, rede e serviços abaixo.

## Critérios de sucesso do disaster recovery

- A aplicação inicia e é atendida pelo Nginx.
- O repositório Git está no commit esperado para o teste.
- MySQL `teste_deploy` foi recuperado em máquina limpa e a aplicação consegue utilizá-lo.
- O registro `DR_TEST_MONGO_001` existe após o restore do MongoDB em máquina limpa.
- O estado `DR_TEST_REDIS_001` existe após o restore do Redis em máquina limpa.
- `storage/app/private/DR_TEST_STORAGE_001.txt` e `scheduler-dr-test.log` existem após o restore no caminho definitivo.
- A tarefa aparece em `php artisan schedule:list`.
- O Cron dispara o Scheduler automaticamente e novas linhas com `DR_TEST_SCHEDULER_001` aparecem em `storage/app/private/scheduler-dr-test.log`.
- Docker, Compose, MongoDB e Redis iniciam com os recursos esperados.
- Portainer inicia com o volume `portainer_data` preservado; o login com usuário existente no backup foi validado em máquina limpa.
- As regras essenciais UFW, o jail `sshd` do Fail2Ban e a configuração Nginx conferem com o inventário validado.

## Pendências após a implementação do laboratório

- Os scripts por componente, o orquestrador, a organização de staging, os manifests, a retenção e o lock estão implementados e validados. Consulte [backup-automation-design.md](backup-automation-design.md).
- Definir criptografia, gestão de chaves e controle de acesso para secrets.
- Formalizar o reprovisionamento do pipeline de backup em host com usuário, caminhos e secrets diferentes.
- Validar a primeira execução diária do **backup** iniciada pelo daemon Cron; o wrapper e a execução manual já foram validados.
- Definir monitoramento ativo, alertas e rotação de logs.
- Definir restore automatizado; o restore manual e o runbook completo já foram validados.
- Decidir o papel real do Redis em produção e, consequentemente, sua necessidade de backup.
- Definir a versão ou digest do Portainer e decidir o momento seguro para encerrar os dados antigos mantidos para rollback em `/var/lib/docker` e `/var/lib/containerd`.
- Definir o escopo de uploads públicos.
- Concluir as pendências de configuração de Nginx, UFW e Fail2Ban antes de declarar uma reconstrução de segurança reproduzível.

## Situação atual

Esta arquitetura foi implementada e validada no laboratório. Os cinco componentes possuem backup automatizado, checksums individuais e manifesto global, staging remoto `.incomplete`, promoção única, permissões restritivas, lock e retenção. O restore point `2026-09-24_173106` foi copiado, validado por SHA-256 e restaurado manualmente em máquina limpa, incluindo aplicação, dados, Nginx, PHP-FPM, build Vite, autenticação e Scheduler por Cron. O disaster recovery geral continua parcialmente validado: secrets, reprodutibilidade entre hosts, uploads públicos, versionamento do Portainer, restore automatizado e observabilidade de produção permanecem abertos.
