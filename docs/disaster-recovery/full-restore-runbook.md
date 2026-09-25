# Runbook manual de disaster recovery completo — TESTE-DEPLOY

> **STATUS: validado em máquina limpa no laboratório.**
>
> A reconstrução validada usou o restore point **2026-09-24_173106** no host limpo **172.23.1.119**, com usuário **sukitas** e projeto em **/home/sukitas/Documentos/laravel-deploy-test/teste-deploy**. Isto comprova o procedimento do laboratório; não declara o DR de produção concluído.

## 1. Escopo e regras de segurança

Este runbook recupera código, configurações entregues separadamente e dados persistentes. O restore point completo contém:

~~~text
mysql/teste_deploy.sql
mongodb/teste_deploy_lab.archive
redis/redis_data.tar.gz
laravel-storage/laravel-storage.tar.gz
portainer/portainer_data.tar.gz
manifest.sha256
~~~

Ele não contém automaticamente:

- .env, infra/.env, APP_KEY, senhas, chaves privadas, tokens ou outros secrets;
- configuração do host, como Nginx, UFW e Fail2Ban;
- infraestrutura de backup do host restaurado;
- uploads futuros em storage/app/public, se existirem;
- restore automatizado.

Antes de começar:

1. Use máquina limpa ou ambiente isolado. Não sobrescreva dados desconhecidos.
2. Nunca restaure a partir de .incomplete/.
3. Pare se qualquer checksum falhar.
4. Não exponha secrets em argumentos, histórico, logs ou Git.
5. Preserve a APP_KEY original; não execute php artisan key:generate.
6. Não rode migrations ou seeders antes de validar o dump e a versão do código.

### Usuários, caminhos e IPs não são portáveis

O host primário usa **lucas-cooperja** e **/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy**. O teste limpo usou **sukitas**, **/home/sukitas/Documentos/laravel-deploy-test/teste-deploy** e **172.23.1.119**.

**Não copie caminhos, usuário, IP ou crontab entre hosts sem adaptar.** No host alvo, defina e confira os próprios valores:

~~~bash
TARGET_USER='sukitas'
PROJECT_ROOT="/home/${TARGET_USER}/Documentos/laravel-deploy-test/teste-deploy"
TARGET_IP='172.23.1.119'
~~~

Os valores acima são apenas a evidência do teste validado.

## 2. Selecionar, copiar e validar o restore point

O destino externo validado no laboratório é **teste@172.23.1.115:/srv/backups/teste-deploy**; esse IP é específico do laboratório.

~~~bash
RUN_ID='2026-09-24_173106'
BACKUP_HOST='teste@172.23.1.115'
BACKUP_ROOT='/srv/backups/teste-deploy'

ssh "$BACKUP_HOST" "
  test -d '$BACKUP_ROOT/$RUN_ID' &&
  test -f '$BACKUP_ROOT/$RUN_ID/manifest.sha256' &&
  cd -- '$BACKUP_ROOT/$RUN_ID' &&
  sha256sum -c manifest.sha256
"
~~~

Copie apenas o diretório promovido para uma área local privada e valide-o novamente:

~~~bash
RESTORE_PARENT="$HOME/teste-deploy-restore"
RESTORE_DIRECTORY="$RESTORE_PARENT/$RUN_ID"
umask 077
mkdir -p "$RESTORE_PARENT"
scp -r "$BACKUP_HOST:$BACKUP_ROOT/$RUN_ID" "$RESTORE_PARENT/"
cd "$RESTORE_DIRECTORY"
sha256sum -c manifest.sha256
~~~

**Sucesso esperado:** os cinco artefatos retornam sucesso no manifesto remoto e local. O manifest de 2026-09-24_173106 passou nas duas validações.

## 3. Preparar a máquina limpa

O laboratório requer Git, PHP 8.3 e PHP-FPM, Composer, MySQL, Nginx, Cron, Docker Engine com Compose, SSH, tar e sha256sum. MongoDB e Redis são serviços Docker definidos em infra/compose.yml, não instalações diretas do host.

~~~bash
git --version
php --version
composer --version
docker --version
docker compose version
mysql --version
nginx -v
systemctl is-active mysql nginx cron docker
~~~

O frontend exige Node.js atual. No teste, Node do APT v18.19.1 com npm 9.2.0 não suportou a dependência atual do Vite. A reconstrução foi concluída com Node v22.23.3 e npm 10.9.9.

~~~bash
node --version
npm --version
~~~

Não reutilize banco ou volume Docker de tentativa anterior sem confirmar que pode ser substituído.

## 4. Recuperar código, dependências e assets

Clone o repositório no caminho do **host alvo**, selecione o commit aprovado e confira o estado:

~~~bash
mkdir -p "$(dirname -- "$PROJECT_ROOT")"
git clone '<URL_DO_REPOSITORIO_APROVADA>' "$PROJECT_ROOT"
cd "$PROJECT_ROOT"
git checkout '<BRANCH_OU_COMMIT_APROVADO>'
git rev-parse --short HEAD
git status --short
composer install --no-interaction --prefer-dist --optimize-autoloader
~~~

O diretório vendor é reconstruível. Em um clone novo, public/build pode não existir. Com Node 22 ou versão compatível:

~~~bash
# Execute somente no clone novo, depois de conferir PROJECT_ROOT.
rm -rf node_modules
npm ci
npm run build
test -f public/build/manifest.json
find public/build/assets -maxdepth 1 -type f \( -name 'app-*.css' -o -name 'app-*.js' \) -print
~~~

**Sucesso esperado:** npm run build termina sem erro e existem public/build/manifest.json, app-*.css e app-*.js. A falha com node:util / styleText sob Node 18 é incompatibilidade de runtime, não falha do backup.

## 5. Aplicar configuração e secrets externos

Entregue .env e infra/.env separadamente, por canal protegido. No host limpo validado:

~~~text
.env       640  <usuário-local>:www-data
infra/.env 600  <usuário-local>:<grupo-local>
~~~

Preserve a APP_KEY, mantenha .env acessível ao runtime PHP-FPM sem leitura pública e mantenha infra/.env privado. Arquivos de senha e chaves de backup permanecem fora do repositório.

## 6. Restaurar MySQL

O banco validado é **teste_deploy**; a conta da aplicação é **laravel@localhost**. Um administrador do host cria ou recupera o banco e essa conta com privilégio mínimo. A conta da aplicação não precisa de privilégio global para criar bancos.

Importe sem senha em argumentos:

~~~bash
mysql --defaults-extra-file='<ARQUIVO_DE_CREDENCIAL_PROTEGIDO>' \
  -u laravel teste_deploy < "$RESTORE_DIRECTORY/mysql/teste_deploy.sql"

mysql --defaults-extra-file='<ARQUIVO_DE_CREDENCIAL_PROTEGIDO>' \
  -u laravel teste_deploy -e '
    SHOW TABLES;
    SELECT COUNT(*) AS users_count FROM users;
    SELECT COUNT(*) AS sessions_count FROM sessions;'
~~~

**Resultado validado:** foram restauradas as tabelas cache, cache_locks, failed_jobs, job_batches, jobs, migrations, password_reset_tokens, sessions e users. As contagens no restore point validado foram **users=2** e **sessions=7108**.

### Erro real: MySQL ERROR 1045

O primeiro teste falhou porque a senha criada para laravel@localhost não correspondia ao secret externo usado pelo .env. A correção foi alinhar a conta local ao secret externamente provisionado. Não gere senha aleatória e não altere o .env sem coordenação; confirme a fonte externa de verdade e alinhe o usuário local a ela.

Não rode migrations ou seeders antes de validar o banco restaurado e a versão da aplicação.

## 7. Restaurar MongoDB

MongoDB usa o container **teste-deploy-mongodb**, imagem **mongo:8.0.32-noble**, banco **teste_deploy_lab** e coleção **recovery_tests**.

~~~bash
cd "$PROJECT_ROOT"
docker compose --env-file infra/.env -f infra/compose.yml up -d mongodb
docker compose --env-file infra/.env -f infra/compose.yml ps mongodb
docker cp "$RESTORE_DIRECTORY/mongodb/teste_deploy_lab.archive" \
  teste-deploy-mongodb:/tmp/teste_deploy_lab.archive
~~~

Use uma configuração temporária protegida para a senha dentro do container, sem senha em argv, e remova-a junto com o archive ao final. O teste limpo usou --drop em container novo:

~~~bash
docker exec -it teste-deploy-mongodb mongorestore \
  --config=/tmp/.mongorestore-config.yml \
  --username lab_mongo_root \
  --authenticationDatabase admin \
  --drop \
  --archive=/tmp/teste_deploy_lab.archive
~~~

Valide apenas o marcador:

~~~javascript
use teste_deploy_lab
db.recovery_tests.find({ identificador: 'DR_TEST_MONGO_001' })
db.recovery_tests.countDocuments()
~~~

**Resultado validado:** um documento foi restaurado, com zero falhas. A consulta correta usa identificador; a consulta antiga usando marker retornava zero e não indicava problema no backup.

## 8. Restaurar Redis

Redis usa **teste-deploy-redis**, imagem **redis:7.4.11-alpine**, AOF e volume nomeado **redis_data**. O archive contém appendonlydir/ e dump.rdb.

No host limpo, pare Redis, confirme que redis_data é o volume de restore e limpe-o **somente se ele não tiver dados a preservar**. Extraia o archive com o volume parado:

~~~bash
cd "$PROJECT_ROOT"
docker compose --env-file infra/.env -f infra/compose.yml stop redis
docker volume inspect redis_data

docker run --rm \
  -v redis_data:/data \
  -v "$RESTORE_DIRECTORY/redis":/restore:ro \
  alpine:3.20 \
  sh -c 'tar -xzf /restore/redis_data.tar.gz -C /data'

docker compose --env-file infra/.env -f infra/compose.yml up -d redis
docker compose --env-file infra/.env -f infra/compose.yml exec -T redis \
  redis-cli GET DR_TEST_REDIS_001
~~~

**Resultado validado:** após o restart, DR_TEST_REDIS_001 retornou disaster-recovery-test. Em produção, a necessidade de backup do Redis continua dependente do papel real do serviço.

## 9. Restaurar storage privado e permissões Laravel

O archive contém a estrutura relativa de storage/app/private/, incluindo:

~~~text
DR_TEST_STORAGE_001.txt
scheduler-dr-test.log
.gitignore
~~~

~~~bash
PRIVATE_STORAGE="$PROJECT_ROOT/storage/app/private"
mkdir -p "$PRIVATE_STORAGE"
tar -xzf "$RESTORE_DIRECTORY/laravel-storage/laravel-storage.tar.gz" -C "$PRIVATE_STORAGE"
grep -F 'DISASTER_RECOVERY_STORAGE_TEST' "$PRIVATE_STORAGE/DR_TEST_STORAGE_001.txt"
grep -F 'DR_TEST_SCHEDULER_001' "$PRIVATE_STORAGE/scheduler-dr-test.log" | tail -1
~~~

No teste, o ownership foi ajustado ao usuário local e grupo www-data. O PHP-FPM precisa ler e gravar em storage, storage/framework, storage/logs e bootstrap/cache:

~~~bash
cd "$PROJECT_ROOT"
sudo chown -R "$TARGET_USER":www-data storage
sudo find storage -type d -exec chmod 775 {} \;
sudo find storage -type f -exec chmod 664 {} \;
sudo chown -R "$TARGET_USER":www-data bootstrap/cache
sudo chmod -R 775 bootstrap/cache

sudo -u www-data test -w bootstrap/cache && echo 'CACHE WRITE OK'
sudo -u www-data php artisan about
sudo -u www-data php artisan optimize:clear
~~~

O erro inicial Target class [view] does not exist não era a causa raiz: a falha efetiva era bootstrap/cache directory must be present and writable. A validação CACHE WRITE OK e php artisan about como www-data confirmaram a correção.

## 10. Restaurar Portainer

Portainer usa o volume **portainer_data** em /data e o socket /var/run/docker.sock. O archive inclui portainer.db e material criptográfico; trate-o como dado sensível.

~~~bash
docker volume create portainer_data
docker run --rm \
  -v portainer_data:/data \
  -v "$RESTORE_DIRECTORY/portainer":/restore:ro \
  alpine:3.20 \
  sh -c 'tar -xzf /restore/portainer_data.tar.gz -C /data'
~~~

O teste iniciou Portainer com a configuração atual portainer/portainer-ce:latest, volume restaurado e Docker socket. O log carregou portainer.db, registrou migração **2.45.0 -> 2.45.1**, iniciou Portainer **2.45.1** e permitiu login com conta existente no backup.

Isto valida o restore e também confirma um gap: latest é mutável. Não escolha uma tag final neste documento. Antes do DR definitivo, confirme no host primário a versão ou digest de origem e fixe referência compatível. A lista de containers não é evidência isolada porque ela vem do Docker socket atual; o login com conta pré-existente é a validação principal.

## 11. Reproduzir Nginx e PHP-FPM

O ambiente usa HTTP na porta 80 e PHP-FPM 8.3 pelo socket /var/run/php/php8.3-fpm.sock. No teste, as zonas foram declaradas em /etc/nginx/conf.d/rate-limits.conf:

~~~nginx
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=3r/s;
limit_req_zone $binary_remote_addr zone=geral_limit:10m rate=30r/s;
~~~

O virtual host validado em /etc/nginx/sites-available/teste.local consolidou os dois blocos PHP existentes no host primário:

~~~nginx
server {
    listen 80;
    server_name 172.23.1.119;
    root /home/sukitas/Documentos/laravel-deploy-test/teste-deploy/public;
    index index.php index.html;

    error_log /var/log/nginx/error.log error;
    access_log /var/log/nginx/laravel_access.log;
    error_log /var/log/nginx/laravel_error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        limit_req zone=login_limit burst=5 nodelay;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
~~~

Adapte server_name e root ao host alvo, crie o link de ativação e valide:

~~~bash
sudo ln -s /etc/nginx/sites-available/teste.local /etc/nginx/sites-enabled/teste.local
sudo nginx -t
sudo systemctl reload nginx
~~~

### ACL necessária quando o projeto fica sob /home/<usuário>

No host limpo, Nginx retornou 404 porque /home/sukitas era 750 e www-data não podia atravessá-lo. Quando o projeto estiver dentro de um home, aplique travessia mínima ao usuário do PHP-FPM:

~~~bash
sudo setfacl -m u:www-data:--x /home/sukitas
sudo -u www-data test -r \
  /home/sukitas/Documentos/laravel-deploy-test/teste-deploy/public/index.php \
  && echo 'OK'
~~~

No teste, o comando retornou OK. Substitua sukitas pelo usuário real do alvo; não abra o home para leitura geral se a ACL mínima resolver.

## 12. Validar aplicação, Vite e autenticação

~~~bash
cd "$PROJECT_ROOT"
php artisan --version
php artisan about
php artisan schedule:list
curl -I "http://$TARGET_IP/"
curl -I "http://$TARGET_IP/login"
~~~

No teste, os drivers eram cache database, banco mysql, fila database e sessão database. A rota / retornou 302 para /login; após o build Vite, GET e HEAD /login retornaram 200.

Se /login retornar 500 e public/build estiver ausente, refaça o build da seção 4. Isto é falha de assets reconstruíveis, não falha dos dados restaurados.

A autenticação com usuário restaurado também foi validada. Como a senha original não era conhecida, ela foi redefinida somente no host limpo de teste, via Laravel Tinker, com credencial temporária fora deste documento. Em ambiente com dados reais, use procedimento de recuperação autorizado; não exponha senha nem altere a origem.

## 13. Validar Scheduler e Cron do Scheduler

O Scheduler é código versionável; o log é dado persistente recuperado no storage. Primeiro execute manualmente:

~~~bash
cd "$PROJECT_ROOT"
CACHE_STORE=file /usr/bin/php artisan schedule:run
tail -n 5 storage/app/private/scheduler-dr-test.log
~~~

No host de teste, o crontab do usuário local continha a linha adaptada ao novo caminho:

~~~cron
* * * * * cd /home/sukitas/Documentos/laravel-deploy-test/teste-deploy && CACHE_STORE=file /usr/bin/php artisan schedule:run >> /dev/null 2>&1
~~~

Valide com:

~~~bash
crontab -l
systemctl is-active cron
grep -c 'DR_TEST_SCHEDULER_001' "$PROJECT_ROOT/storage/app/private/scheduler-dr-test.log"
tail -n 10 "$PROJECT_ROOT/storage/app/private/scheduler-dr-test.log"
~~~

**Resultado validado:** havia 7 linhas às 18:09 e 10 após três minutos. Foram registradas novas linhas às 2026-09-25 18:10:02, 18:11:01 e 18:12:02 com DR_TEST_SCHEDULER_001. Isso valida Cron -> artisan schedule:run -> Scheduler Laravel -> storage privado.

## 14. Reprovisionar backup é uma etapa separada

Não copie diretamente o Cron de backup do primário para o host restaurado. O wrapper atual scripts/disaster-recovery/run-backup-cron.sh depende de usuário e caminhos do host primário lucas-cooperja, da partição /srv/teste-deploy-data, de arquivos externos de credencial, de chave SSH dedicada e de acesso ao destino externo.

No host primário, a execução automática do pipeline pelo daemon Cron foi validada em 2026-09-25. O teste das 02:00 não ocorreu porque host e Cron só ficaram ativos por volta de 13:22; isso não representou falha do pipeline. Em teste controlado para 16:05, o daemon iniciou o wrapper às 16:05:01, gerou o RUN_ID 2026-09-25_160501 e concluiu os cinco componentes, manifesto remoto, promoção, retenção e validação externa do manifesto com sucesso.

Essa evidência não torna a configuração portável nem elimina o risco operacional: Cron tradicional não recupera automaticamente uma execução perdida enquanto o host ou o serviço estiver desligado. A futura reprovisão deve avaliar um systemd timer persistente ou estratégia equivalente.

Para habilitar backup no novo host, reprovisione e valide separadamente:

1. mount, staging, logs, lock, ownership e permissões locais;
2. arquivos externos de secrets, sem colocá-los no Git;
3. chave SSH dedicada e acesso ao servidor externo;
4. usuário local, HOME, caminho de projeto e parâmetros do novo host;
5. Cron de backup adaptado e testado manualmente antes do agendamento.

## 15. Checklist de sucesso validado

- [x] Manifesto remoto e local aprovado.
- [x] MySQL restaurado com estrutura e contagens esperadas.
- [x] MongoDB recuperou DR_TEST_MONGO_001.
- [x] Redis recuperou DR_TEST_REDIS_001 após restart.
- [x] Storage privado recuperou DR_TEST_STORAGE_001.txt e o log do Scheduler.
- [x] Portainer carregou portainer.db e autenticou conta existente no backup.
- [x] Nginx passou em nginx -t e PHP-FPM alcançou o projeto após ACL e permissões.
- [x] Laravel inicializou como www-data; bootstrap/cache ficou gravável.
- [x] Vite foi reconstruído com Node 22; /login retornou 200.
- [x] Autenticação funcional foi confirmada.
- [x] Scheduler funcionou manualmente e automaticamente via Cron.

## 16. Troubleshooting baseado no teste real

| Sintoma | Causa confirmada | Ação segura |
|---|---|---|
| MySQL ERROR 1045 | Senha de laravel@localhost divergente do secret externo. | Alinhar a conta local ao secret provisionado; não inventar senha. |
| Nginx 404 | www-data não tinha travessia no home do usuário. | ACL mínima u:www-data:--x e teste de leitura de public/index.php. |
| Laravel 500 / Target class [view] does not exist | Causa raiz: bootstrap/cache não gravável. | Corrigir ownership e modo de storage e bootstrap/cache; testar como www-data. |
| Vite falha com node:util / styleText | Node 18 incompatível. | Usar Node 22 compatível, npm ci e npm run build. |
| /login retorna 500 | public/build ausente. | Gerar assets e validar manifest. |
| Mongo retorna zero para marcador | Consulta usou marker em vez de identificador. | Consultar { identificador: 'DR_TEST_MONGO_001' }. |
| Portainer migra banco no startup | latest puxou versão diferente. | Preservar volume/logs e definir tag ou digest após conferir a origem. |

Esses casos foram falhas de reprovisionamento/configuração no host limpo, não falhas do backup validado.

## 17. Gaps ainda abertos

- Fixar Portainer em tag ou digest após verificar a versão do host primário.
- Definir gestão de secrets de produção.
- Tornar a automação de backup parametrizável ou reprovisionável em host com outro usuário e caminho.
- Definir e validar escopo de uploads públicos em storage/app/public.
- Manter cópia em destino fisicamente externo; a NVMe local é staging/capacidade, não proteção contra perda física.
- Criar restore automatizado somente após aprovação do processo manual.

## 18. Referências

- [Arquitetura de backup e restore](backup-architecture.md)
- [Desenho da automação](backup-automation-design.md)
- [Orquestrador de backup](backup-orchestrator.md)
- [Cron e monitoramento básico](backup-cron.md)
- [Inventário Laravel](../inventario/laravel.md), [MySQL](../inventario/mysql.md), [MongoDB](../inventario/mongodb.md), [Redis](../inventario/redis.md), [Portainer](../inventario/portainer.md), [Nginx](../inventario/nginx.md), [Cron](../inventario/cron.md) e [secrets](../inventario/secrets.md)
