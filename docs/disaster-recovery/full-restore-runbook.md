# Runbook manual de disaster recovery completo — TESTE-DEPLOY

> **STATUS: preparado, ainda não validado em máquina limpa.**

## 1. Objetivo, escopo e premissas

Este runbook orienta a reconstrução manual do laboratório `TESTE-DEPLOY` em uma máquina limpa, usando:

- o repositório Git e o commit desejado;
- um restore point completo já promovido no servidor externo;
- os documentos de inventário e de backup/restore por componente;
- secrets e configurações entregues por canal protegido, fora do Git e fora do restore point de dados.

Ele não é um script e não autoriza executar comandos cegamente em uma máquina com dados desconhecidos. Execute cada seção manualmente, confirme o resultado indicado e interrompa ao primeiro erro de integridade, conflito de dados ou configuração não disponível.

O restore point completo contém os artefatos abaixo, com caminhos relativos à raiz da execução:

```text
mysql/teste_deploy.sql
mongodb/teste_deploy_lab.archive
redis/redis_data.tar.gz
laravel-storage/laravel-storage.tar.gz
portainer/portainer_data.tar.gz
manifest.sha256
```

Não estão incluídos automaticamente:

- `.env`, `infra/.env`, `APP_KEY`, senhas, chaves privadas, tokens e demais secrets;
- configurações customizadas do host, como Nginx, UFW e Fail2Ban;
- uploads futuros em `storage/app/public`, caso passem a existir;
- um mecanismo automático de restore, alertas ou criptografia de secrets.

## 2. Regras de segurança antes de começar

1. Trabalhe em uma máquina realmente limpa ou em ambiente isolado. Para testes parciais, use bancos, volumes e portas isolados.
2. Não restaure sobre um banco, volume ou diretório cujo conteúdo não tenha sido identificado. Pare e faça uma cópia de segurança independente antes de substituir qualquer dado conhecido.
3. Nunca use um diretório sob `.incomplete/` como restore point.
4. Nunca continue se `sha256sum -c manifest.sha256` falhar.
5. Não escreva secrets em comandos, histórico do shell, arquivos versionados ou logs. Forneça-os apenas por canal protegido e com permissões restritivas.
6. Registre o `RUN_ID`, o commit Git, os comandos executados e os resultados das validações em um registro operacional fora do repositório.

## 3. Escolher e validar o restore point

O destino externo atual do laboratório é `teste@172.23.1.115:/srv/backups/teste-deploy`. O IP é específico deste laboratório; em outro ambiente, descubra e valide o destino antes de continuar.

Defina o identificador escolhido no formato `YYYY-MM-DD_HHMMSS`:

```bash
RUN_ID='<RUN_ID_PROMOVIDO>'
BACKUP_HOST='teste@172.23.1.115'
BACKUP_ROOT='/srv/backups/teste-deploy'
```

Liste somente os diretórios diretos candidatos e confirme visualmente que o `RUN_ID` escolhido está fora de `.incomplete/`:

```bash
ssh "$BACKUP_HOST" \
  "find '$BACKUP_ROOT' -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r"
```

Antes de baixar, confirme que o diretório promovido e o manifesto existem e que o manifesto valida no próprio destino de backup:

```bash
ssh "$BACKUP_HOST" "
  test -d '$BACKUP_ROOT/$RUN_ID' &&
  test -f '$BACKUP_ROOT/$RUN_ID/manifest.sha256' &&
  ! test -L '$BACKUP_ROOT/$RUN_ID/manifest.sha256' &&
  cd -- '$BACKUP_ROOT/$RUN_ID' &&
  sha256sum -c manifest.sha256
"
```

**Resultado esperado:** todos os cinco artefatos devem retornar `SUCESSO` ou `OK`, conforme a localidade do comando. Se houver falha, não use esse `RUN_ID`; investigue o destino externo e escolha outro restore point promovido.

## 4. Preparar a máquina limpa

O laboratório atual usa uma base Linux Mint/Ubuntu, MySQL, Nginx e Cron no host, além de Docker para MongoDB, Redis e Portainer. Confirme a versão disponível e compare-a com os inventários antes de instalar: PHP 8.3, MySQL 8.0, Nginx 1.24 e imagens Docker documentadas são as referências atuais do laboratório.

Em Debian, Ubuntu ou Linux Mint, os comandos abaixo são um ponto de partida manual. Eles não devem ser executados automaticamente por este documento:

```bash
sudo apt update
sudo apt install \
  git docker.io docker-compose-plugin \
  php8.3-cli php8.3-fpm php8.3-mysql php8.3-curl php8.3-mbstring php8.3-xml php8.3-zip \
  composer nginx mysql-server cron openssh-client tar coreutils
```

Depois, valide as ferramentas e serviços essenciais:

```bash
git --version
php --version
composer --version
docker --version
docker compose version
mysql --version
nginx -v
systemctl is-active mysql nginx cron docker
```

Se o usuário que executará Docker não tiver acesso ao socket, aplique a política local de grupo `docker` conscientemente e abra uma nova sessão antes de seguir. A associação ao grupo dá acesso administrativo ao Docker e não deve ser tratada como detalhe inofensivo.

MongoDB e Redis não exigem instalação direta no host neste laboratório: serão iniciados por `infra/compose.yml`. Não instale ou use volumes de bancos de uma tentativa anterior sem antes decidir explicitamente se podem ser descartados.

## 5. Recuperar o repositório e as dependências

O caminho usado no laboratório atual é:

```text
/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy
```

Uma máquina limpa pode manter esse caminho para compatibilidade com a configuração Nginx já inventariada, ou usar outro caminho desde que o virtual host seja revisado para apontar ao novo `public/`.

Clone o repositório e escolha o commit ou branch aprovado para o teste:

```bash
PROJECT_ROOT='/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy'
mkdir -p "$(dirname -- "$PROJECT_ROOT")"
git clone '<URL_DO_REPOSITORIO_FORNECIDA_SEPARADAMENTE>' "$PROJECT_ROOT"
cd "$PROJECT_ROOT"
git checkout '<BRANCH_OU_COMMIT_APROVADO>'
git rev-parse --short HEAD
git status --short
```

**Resultado esperado:** o commit exibido deve corresponder ao registro operacional do restore e o working tree deve estar limpo antes dos dados não versionados serem restaurados.

Instale dependências PHP a partir do lockfile:

```bash
composer install --no-interaction --prefer-dist --optimize-autoloader
```

`vendor/` é reconstruível e não vem do backup. Se o processo de entrega exigir assets front-end, avalie separadamente `npm ci` e o comando de build definido pelo projeto; não invente uma etapa de build sem confirmar essa necessidade.

## 6. Fornecer configurações e secrets externamente

Antes de iniciar serviços que dependam de credenciais, obtenha por canal protegido e aplique com modo restritivo:

- `.env` da aplicação ou seus valores necessários;
- `APP_KEY` original da aplicação;
- dados de conexão e credenciais MySQL;
- credencial administrativa do MongoDB;
- `infra/.env` para o Compose, se aplicável;
- credenciais de runtime adicionais, como e-mail, AWS/S3 ou Redis, caso estejam realmente em uso;
- chave SSH de backup somente se esta máquina também for enviar ou consultar backups diretamente.

Use arquivos protegidos entregues separadamente. Por exemplo, para um `.env` já obtido de fonte confiável:

```bash
install -m 600 '<CAMINHO_PROTEGIDO_DO_ENV>' "$PROJECT_ROOT/.env"
install -m 600 '<CAMINHO_PROTEGIDO_DO_INFRA_ENV>' "$PROJECT_ROOT/infra/.env"
```

Substitua os placeholders apenas no terminal da pessoa autorizada; não registre os valores em tickets, Git ou logs. Não gere uma nova `APP_KEY` quando o objetivo for recuperar dados já criptografados: mudar essa chave pode tornar valores existentes irrecuperáveis.

O backup de dados não substitui a gestão de secrets e configurações. Sem essas entradas externas, a reconstrução pode restaurar os dados, mas não necessariamente inicializar a aplicação ou autenticar nos serviços.

## 7. Baixar e validar novamente o restore point

Use uma área local isolada, com permissões privadas. O exemplo abaixo pressupõe que a chave SSH, se necessária, foi fornecida externamente; não coloque seu conteúdo no repositório.

```bash
RESTORE_PARENT="$HOME/teste-deploy-restore"
RESTORE_DIRECTORY="$RESTORE_PARENT/$RUN_ID"
umask 077
mkdir -p "$RESTORE_PARENT"

scp -r "$BACKUP_HOST:$BACKUP_ROOT/$RUN_ID" "$RESTORE_PARENT/"
cd "$RESTORE_DIRECTORY"
sha256sum -c manifest.sha256
```

Se o acesso exigir a chave dedicada, acrescente somente a referência protegida com `-i <CAMINHO_DA_CHAVE>` ao `ssh` e ao `scp`; não copie a chave para o diretório de restore.

**Resultado esperado:** o diretório local contém os cinco subdiretórios de componente e `manifest.sha256`; todos os hashes são aprovados. Não restaure componente algum antes dessa segunda validação.

## 8. Ordem manual de restore

Siga esta ordem para reduzir dependências e evitar que serviços gravem em dados ainda incompletos:

1. preparar sistema operacional, ferramentas e capacidade local;
2. recuperar o repositório e receber secrets/configurações separadamente;
3. preparar MySQL e restaurar `teste_deploy`;
4. preparar MongoDB e restaurar `teste_deploy_lab`;
5. restaurar o volume Redis antes de iniciar o container Redis;
6. restaurar `storage/app/private`;
7. restaurar o volume `portainer_data` antes de iniciar Portainer;
8. concluir preparação Laravel e validar conexões;
9. aplicar/reproduzir configurações Nginx validadas e ativar o site;
10. recriar os agendamentos de Scheduler e backup no crontab correto;
11. executar a validação final.

Essa ordem é um procedimento proposto para máquina limpa. Ela ainda não foi validada de ponta a ponta no laboratório.

## 9. Restaurar MySQL

O MySQL é um serviço do host e o artefato é um dump lógico. Confira primeiro se não existe banco com dados desconhecidos:

```bash
sudo systemctl enable --now mysql
sudo mysql -e "SHOW DATABASES LIKE 'teste_deploy';"
```

Se o banco já existir, pare. Em máquina limpa, crie o banco somente após confirmar o nome e a política de caracteres definida para o ambiente:

```bash
sudo mysql -e 'CREATE DATABASE `teste_deploy`;'
```

Crie ou recupere a conta de aplicação por um procedimento administrativo protegido, concedendo apenas os privilégios necessários sobre `teste_deploy`. O usuário da aplicação não deve receber privilégio global para criar bancos; esse princípio de menor privilégio foi validado no laboratório.

Importe usando uma credencial fornecida externamente, sem senha em argumento. Exemplo conceitual com arquivo de opções protegido:

```bash
mysql --defaults-extra-file='<ARQUIVO_MYSQL_PROTEGIDO>' \
  -u '<USUARIO_DA_APLICACAO>' \
  teste_deploy < "$RESTORE_DIRECTORY/mysql/teste_deploy.sql"
```

Valide estrutura e contagens sem exibir dados de usuários:

```bash
mysql --defaults-extra-file='<ARQUIVO_MYSQL_PROTEGIDO>' \
  -u '<USUARIO_DA_APLICACAO>' \
  teste_deploy -e 'SHOW TABLES; SELECT COUNT(*) AS users_count FROM users; SELECT COUNT(*) AS sessions_count FROM sessions;'
```

**Resultado esperado:** as tabelas Laravel, incluindo `migrations`, `users`, `sessions`, `cache`, `jobs` e tabelas relacionadas, devem existir. As contagens podem diferir do teste histórico porque variam conforme o restore point escolhido. Não execute migrations ou seeders cegamente após importar: primeiro compare `php artisan migrate:status` com o estado restaurado.

## 10. Restaurar MongoDB

O Compose versionável define `teste-deploy-mongodb`, a imagem `mongo:8.0.32-noble`, o banco `teste_deploy_lab` e o volume `mongodb_data`. Com `infra/.env` já fornecido externamente, inicie somente o serviço MongoDB para criar ou localizar o volume:

```bash
cd "$PROJECT_ROOT"
docker compose --env-file infra/.env -f infra/compose.yml up -d mongodb
docker compose --env-file infra/.env -f infra/compose.yml ps mongodb
```

Copie o archive para o container. Em máquina limpa, o banco deve estar vazio; se já houver dados, pare e restaure em banco isolado antes de decidir qualquer sobrescrita.

```bash
docker cp "$RESTORE_DIRECTORY/mongodb/teste_deploy_lab.archive" \
  teste-deploy-mongodb:/tmp/teste_deploy_lab.archive
```

Dentro de uma sessão interativa no container, crie temporariamente um arquivo YAML privado para a senha fornecida externamente. Não passe a senha em `--password`, não a ponha em um `docker exec` registrado e remova o arquivo ao terminar:

```bash
docker exec -it teste-deploy-mongodb sh
umask 077
cat > /tmp/.mongorestore-config.yml
# Informe somente na sessão interativa: password: <valor fornecido externamente>
mongorestore \
  --config=/tmp/.mongorestore-config.yml \
  --username lab_mongo_root \
  --authenticationDatabase admin \
  --archive=/tmp/teste_deploy_lab.archive \
  --nsInclude='teste_deploy_lab.*'
rm -f /tmp/.mongorestore-config.yml /tmp/teste_deploy_lab.archive
exit
```

Para validar, conecte-se de forma interativa ao `mongosh` com a credencial externa e consulte apenas o marcador:

```javascript
use teste_deploy_lab
db.recovery_tests.find({ identificador: 'DR_TEST_MONGO_001' })
db.recovery_tests.countDocuments()
```

**Resultado esperado:** o marcador `DR_TEST_MONGO_001` existe na coleção `recovery_tests` e a contagem é compatível com o restore point. A autenticação usa `admin` como `authenticationDatabase`.

## 11. Restaurar Redis

Redis usa a imagem `redis:7.4.11-alpine`, AOF habilitado, o container `teste-deploy-redis` e o volume nomeado `redis_data`. O archive contém o diretório AOF e `dump.rdb`.

Redis não pode estar escrevendo no volume durante a extração. Em uma máquina limpa, crie o volume e confirme que ele está vazio antes de restaurar:

```bash
docker volume create redis_data
docker run --rm \
  -v redis_data:/data \
  -v "$RESTORE_DIRECTORY/redis":/restore:ro \
  alpine:3.20 \
  sh -c 'test -z "$(find /data -mindepth 1 -maxdepth 1 -print -quit)" && tar -xzf /restore/redis_data.tar.gz -C /data'
```

Se o volume não estiver vazio, o comando falha deliberadamente. Não limpe o volume sem confirmar que ele não contém dado a preservar. Depois da extração, inicie Redis pelo Compose:

```bash
cd "$PROJECT_ROOT"
docker compose --env-file infra/.env -f infra/compose.yml up -d redis
docker compose --env-file infra/.env -f infra/compose.yml exec -T redis \
  redis-cli GET DR_TEST_REDIS_001
```

**Resultado esperado:** o container está ativo e a chave retorna o valor esperado do marcador. No laboratório, isso comprovou a recuperação de estado persistente; em produção, a necessidade de backup Redis depende do seu papel real.

## 12. Restaurar o storage privado do Laravel

O archive `laravel-storage.tar.gz` contém o conteúdo relativo de `storage/app/private/`, incluindo `DR_TEST_STORAGE_001.txt`, `scheduler-dr-test.log` e `.gitignore` no restore point validado.

Primeiro, confirme que o destino não contém dados inesperados. Em um clone limpo, apenas o arquivo de controle do Git pode existir; se houver outros arquivos, pare e investigue:

```bash
PRIVATE_STORAGE="$PROJECT_ROOT/storage/app/private"
mkdir -p "$PRIVATE_STORAGE"
find "$PRIVATE_STORAGE" -mindepth 1 -maxdepth 1 ! -name '.gitignore' -print
```

Depois da inspeção, extraia preservando a estrutura relativa:

```bash
tar -xzf "$RESTORE_DIRECTORY/laravel-storage/laravel-storage.tar.gz" -C "$PRIVATE_STORAGE"
test -f "$PRIVATE_STORAGE/DR_TEST_STORAGE_001.txt"
grep -F 'DISASTER_RECOVERY_STORAGE_TEST' "$PRIVATE_STORAGE/DR_TEST_STORAGE_001.txt"
grep -F 'DR_TEST_SCHEDULER_001' "$PRIVATE_STORAGE/scheduler-dr-test.log" | tail -1
```

As permissões e o ownership armazenados no archive precisam ser conferidos no destino. O teste de extração isolada observou, por exemplo, arquivos `664` e `.gitignore` `775`; isso não foi tratado como falha do backup. Identifique o usuário/grupo efetivo do PHP-FPM no host alvo e ajuste somente o necessário para que o processo da aplicação leia/escreva em `storage/` sem conceder permissões amplas.

**Resultado esperado:** o marcador privado existe com o conteúdo correto e o log do Scheduler contém o marcador histórico. O conteúdo de `storage/app/private` é dado persistente e não é recuperado por Git.

## 13. Restaurar Portainer

O Portainer usa o container `portainer`, o volume `portainer_data`, destino `/data`, Docker socket em `/var/run/docker.sock` e HTTPS na porta 9443. O archive preserva o estado, incluindo `portainer.db` e chaves privadas; trate-o como dado sensível.

Em máquina limpa, restaure o volume antes de iniciar Portainer e confirme que o volume não contém dados inesperados:

```bash
docker volume create portainer_data
docker run --rm \
  -v portainer_data:/data \
  -v "$RESTORE_DIRECTORY/portainer":/restore:ro \
  alpine:3.20 \
  sh -c 'test -z "$(find /data -mindepth 1 -maxdepth 1 -print -quit)" && tar -xzf /restore/portainer_data.tar.gz -C /data'
```

O laboratório atual usa `portainer/portainer-ce:latest`, uma tag mutável. Antes de um DR definitivo, obtenha uma versão ou digest conhecido e compatível com o backup. Não substitua esse ponto por uma suposição de que `latest` continuará equivalente:

```bash
PORTAINER_IMAGE='<VERSAO_OU_DIGEST_VALIDADO_EXTERNAMENTE>'
docker pull "$PORTAINER_IMAGE"
docker run -d \
  --name portainer \
  --restart always \
  -p 9443:9443 \
  -v portainer_data:/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$PORTAINER_IMAGE"
```

Valide o container e o acesso HTTPS. A evidência funcional de persistência é autenticar com uma conta que existia antes do backup, usando credenciais fornecidas fora deste documento. A lista de containers vista na interface não basta por si só, pois ela é fornecida pelo Docker socket atual.

## 14. Preparar e validar Laravel

Com `.env`, banco, storage e serviços disponíveis, faça apenas validações não destrutivas primeiro:

```bash
cd "$PROJECT_ROOT"
php artisan --version
php artisan about
php artisan migrate:status
php artisan schedule:list
```

Não execute migrations, seeders, `key:generate`, limpeza de cache ou workers cegamente depois de um restore. Primeiro confirme que:

- o `.env` tem a `APP_KEY` original e os dados de conexão corretos;
- MySQL, MongoDB e Redis estão no estado esperado;
- `storage/app/private` está presente e gravável pelo runtime;
- os diretórios temporários `storage/framework` e caches podem ser reconstruídos conforme a necessidade, sem apagar dados persistentes.

Quando a configuração estiver confirmada, valide a aplicação pelo fluxo definido pelo projeto. O Laravel atual usa MySQL para cache, sessão e fila; Redis não é uma dependência atual do Laravel neste laboratório.

## 15. Reproduzir e ativar Nginx

Nginx é um serviço do host. O inventário confirma a configuração principal em `/etc/nginx/nginx.conf`, o virtual host em `/etc/nginx/sites-available/teste.local`, o link em `/etc/nginx/sites-enabled/teste.local`, PHP-FPM 8.3 via `/var/run/php/php8.3-fpm.sock` e HTTP na porta 80. HTTPS não está configurado no laboratório atual.

Esses arquivos não fazem parte do restore point de dados. Recupere-os do canal de configuração/versionamento definido separadamente e revise o `root` do virtual host para garantir que corresponde ao `public/` do clone. Somente depois disso, ative e teste:

```bash
sudo ln -s /etc/nginx/sites-available/teste.local /etc/nginx/sites-enabled/teste.local
sudo nginx -t
sudo systemctl reload nginx
```

Se o link já existir ou a configuração divergir, pare e revise em vez de sobrescrever. **Resultado esperado:** `nginx -t` aprova a configuração e a aplicação responde pela rota configurada. Consulte [nginx.md](../inventario/nginx.md) para rate limits, logs e pendências conhecidas.

## 16. Scheduler e Cron

O Scheduler Laravel é código versionável em `routes/console.php`; o log que ele gera foi restaurado junto com o storage privado. Valide-o manualmente antes de depender do agendamento:

```bash
cd "$PROJECT_ROOT"
CACHE_STORE=file /usr/bin/php artisan schedule:run
tail -n 5 storage/app/private/scheduler-dr-test.log
```

O crontab do usuário `lucas-cooperja` precisa conter a tarefa do Scheduler e, no laboratório atual, a tarefa diária do backup:

```cron
* * * * * cd /home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy && CACHE_STORE=file /usr/bin/php artisan schedule:run >> /dev/null 2>&1
0 2 * * * /home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy/scripts/disaster-recovery/run-backup-cron.sh
```

Instale ou revise essas linhas manualmente com `crontab -e` no usuário correto, depois valide:

```bash
crontab -l
systemctl is-active cron
```

O backup Cron depende dos arquivos protegidos de credenciais e da chave SSH, fornecidos fora do Git. Consulte [backup-cron.md](backup-cron.md) para o monitoramento por `cron-backup.log`, comportamento de `flock` e a validação da janela agendada. A primeira execução iniciada pelo daemon às 02:00 ainda não foi validada no laboratório.

## 17. Checklist de validação final

Conclua o teste somente quando todos os itens aplicáveis estiverem aprovados:

- [ ] O `RUN_ID` escolhido era promovido, tinha `manifest.sha256` e passou no SHA-256 remoto e local.
- [ ] O repositório está no commit esperado e dependências PHP foram instaladas a partir de `composer.lock`.
- [ ] O `.env`, `APP_KEY` e demais secrets foram fornecidos por canal protegido, sem entrar no Git.
- [ ] MySQL está acessível e `teste_deploy` possui as tabelas e contagens esperadas para o restore point.
- [ ] `DR_TEST_MONGO_001` existe em `teste_deploy_lab.recovery_tests`.
- [ ] `DR_TEST_REDIS_001` existe após o Redis iniciar com AOF e volume restaurado.
- [ ] `storage/app/private/DR_TEST_STORAGE_001.txt` existe e contém o marcador esperado.
- [ ] `scheduler-dr-test.log` contém `DR_TEST_SCHEDULER_001` e novas linhas podem ser geradas pela tarefa.
- [ ] Portainer responde em HTTPS e a autenticação com conta pré-existente no backup é possível.
- [ ] Nginx aprova `nginx -t` e atende a aplicação com PHP-FPM.
- [ ] `cron.service` está ativo, o Scheduler está no crontab correto e o wrapper de backup está executável.
- [ ] Os logs de backup não apresentam `FAILED`, falha de componente ou erro de integridade crítico para a execução escolhida.

## 18. Parada, rollback e tratamento de falhas

| Situação | Ação imediata | Como saber se é seguro continuar |
|---|---|---|
| Manifesto ou checksum falha | Pare; não extraia nem importe o artefato. Baixe novamente ou escolha outro restore point promovido. | Todos os itens de `sha256sum -c manifest.sha256` passam. |
| Banco ou volume de destino já contém dados | Pare; não sobrescreva. Faça cópia independente ou use nome/volume isolado para testar. | O destino está vazio ou sua substituição foi aprovada e registrada. |
| Secret/configuração indisponível | Pare antes de iniciar a aplicação ou o serviço dependente. | A configuração foi entregue por canal protegido, com permissões adequadas. |
| MongoDB, Redis ou Portainer não iniciam | Preserve logs e volume restaurado; não recrie o volume automaticamente. Compare imagem, Compose e permissões com o inventário. | O serviço inicia e o marcador ou estado funcional é validado. |
| Nginx falha em `nginx -t` | Não faça reload. Revise os arquivos recuperados e o caminho do projeto. | O teste sintático é aprovado. |
| Scheduler/Cron não escreve marcador | Execute `schedule:run` manualmente e revise usuário, PHP absoluto, `CACHE_STORE=file` e crontab. | A execução manual funciona antes de aguardar o Cron. |

Em qualquer rollback de teste, prefira remover apenas os bancos, volumes e containers explicitamente criados para o teste isolado. Não use comandos globais como `docker system prune`, não apague restore points externos e não substitua dados desconhecidos.

## 19. Referências

- [Arquitetura de backup e restore](backup-architecture.md)
- [Desenho da automação](backup-automation-design.md)
- [Orquestrador de backup](backup-orchestrator.md)
- [Cron e monitoramento básico](backup-cron.md)
- [Backup e restore MySQL](mysql-backup-restore.md)
- [Backup e restore MongoDB](mongodb-backup-restore.md)
- [Backup e restore Redis](redis-backup-restore.md)
- [Backup e restore Laravel storage](laravel-storage-backup-restore.md)
- [Backup e restore Portainer](portainer-backup-restore.md)
- [Inventário Laravel](../inventario/laravel.md), [storage](../inventario/laravel-storage.md), [MySQL](../inventario/mysql.md), [MongoDB](../inventario/mongodb.md), [Redis](../inventario/redis.md), [Portainer](../inventario/portainer.md), [Nginx](../inventario/nginx.md), [Cron](../inventario/cron.md) e [secrets](../inventario/secrets.md)

## 20. Limites do status atual

Este runbook consolida evidências de restores isolados e fluxos de backup já validados no laboratório. Ele **não** comprova uma reconstrução completa em máquina limpa, não automatiza restore e não declara o disaster recovery concluído. A execução integral deste documento em uma segunda máquina é a próxima validação necessária.
