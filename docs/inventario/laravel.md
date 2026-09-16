# Laravel — TESTE-DEPLOY

## Aplicação e ambiente

- Projeto: `/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy`
- Laravel Framework: 13.27.0
- PHP CLI: 8.3.6
- Composer: 2.7.1
- Ambiente informado: `local`
- Debug: habilitado
- Maintenance mode: desabilitado
- Timezone: `UTC`
- Locale: `en`

Estruturas principais identificadas: `app`, `bootstrap`, `config`, `database`, `public`, `resources`, `routes`, `storage`, `tests`, `vendor` e `node_modules`.

## Configuração efetiva identificada

| Área | Configuração efetiva | Persistência/impacto |
|---|---|---|
| Banco principal | MySQL | Dados de aplicação residem no banco; devem ser inventariados separadamente. |
| Cache | `database` | Dados de cache ficam no MySQL; são temporários/reconstruíveis em princípio. |
| Session | `database` | Sessões ficam no MySQL; são temporárias, mas sua perda encerra sessões ativas. |
| Queue | `database` | Jobs pendentes, batches e falhas podem residir no MySQL. |
| Logs | `stack` com canal `single` | Arquivo local em `storage/logs/laravel.log`. |
| Filesystem padrão | `local` | Disco local privado em `storage/app/private`. |
| Broadcasting | `log` | Sem infraestrutura externa de broadcast identificada. |
| Mail | `log` | Sem transporte externo de e-mail identificado pela configuração efetiva. |

Configuração de cache, eventos e rotas: não cacheada. Views: cacheadas.

## Filesystems

| Disco | Driver | Caminho | Estado identificado |
|---|---|---|---|
| `local` | `local` | `storage/app/private` | Disco padrão efetivo; diretório sem arquivos de aplicação identificados. |
| `public` | `local` | `storage/app/public` | Definido para conteúdo público; diretório sem arquivos de aplicação identificados. |
| `s3` | `s3` | Serviço externo potencial | Definido no arquivo padrão de configuração, mas não há evidência de uso ativo. |

O link configurado entre `public/storage` e `storage/app/public` não existe no momento do levantamento.

## Filas e workers

- Driver efetivo: `database`.
- Configuração declarada: tabela de jobs `jobs`; batches em `job_batches`; falhas em `failed_jobs` quando as migrations correspondentes existirem.
- Não foi encontrado diretório `app/Jobs`, nem referências a `ShouldQueue`, `dispatch`, `Queue` ou `Bus` no código inspecionado.
- Não foram identificadas unidades systemd, configurações Supervisor ou processos ativos de `queue:work`, `queue:listen` ou Horizon.
- Redis aparece apenas como configuração disponível; não é o driver de fila, cache ou sessão efetivo.

## Arquivos de ambiente e variáveis relevantes

Existem `.env` e `.env.example` na raiz do projeto. Somente os nomes das variáveis foram inspecionados.

| Área | Variáveis identificadas |
|---|---|
| Aplicação | `APP_NAME`, `APP_ENV`, `APP_KEY`, `APP_DEBUG`, `APP_URL`, `APP_LOCALE`, `APP_FALLBACK_LOCALE`, `APP_FAKER_LOCALE`, `APP_MAINTENANCE_DRIVER`, `BCRYPT_ROUNDS` |
| Logs | `LOG_CHANNEL`, `LOG_STACK`, `LOG_DEPRECATIONS_CHANNEL`, `LOG_LEVEL` |
| Banco | `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` |
| Sessão | `SESSION_DRIVER`, `SESSION_LIFETIME`, `SESSION_ENCRYPT`, `SESSION_PATH`, `SESSION_DOMAIN` |
| Cache e fila | `CACHE_STORE`, `QUEUE_CONNECTION` |
| Filesystem | `FILESYSTEM_DISK` |
| Redis/Memcached | `REDIS_CLIENT`, `REDIS_HOST`, `REDIS_PASSWORD`, `REDIS_PORT`, `MEMCACHED_HOST` |
| E-mail | `MAIL_MAILER`, `MAIL_SCHEME`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME` |
| AWS/S3 | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `AWS_BUCKET`, `AWS_USE_PATH_STYLE_ENDPOINT` |
| Front-end | `VITE_APP_NAME` |

Nenhum valor de `.env`, chave, senha, token ou credencial foi registrado neste documento.

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| Código Laravel (`app`, `routes`, `config`, `resources`, `database`) | Código/configuração | Preservar por versionamento e reproduzir no deploy. |
| `.env` | Configuração com secrets | Preservar de modo protegido; não versionar valores reais. |
| `.env.example` | Configuração documentável | Versionar somente nomes e exemplos sem dados reais. |
| MySQL | Dado persistente | Inventariar tabelas e dados separadamente. |
| Cache no banco | Cache/temporário | Reconstruível; validar impacto operacional antes de descartar. |
| Sessões no banco | Temporário operacional | Não essencial ao restore básico, mas sua perda afeta sessões ativas. |
| Filas no banco | Dado operacional potencialmente persistente | Validar tabelas e jobs pendentes antes de recuperação. |
| `vendor/` | Dependência reconstruível | 165 MB; reproduzível a partir de `composer.lock`. |
| `node_modules/` | Dependência reconstruível | 233 MB; reproduzível a partir de `package-lock.json`. |
| `bootstrap/cache` | Cache/temporário | 60 KB; não há config, evento ou rota cacheados no levantamento. |

## Pendências

- Inventariar MySQL separadamente, incluindo a existência das tabelas de sessão, cache e filas.
- Confirmar se o disco S3 será usado no futuro; não há uso ativo identificado.
- Verificar futuramente se `local` e debug habilitado são adequados ao ambiente-alvo.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento da aplicação Laravel no ambiente `TESTE-DEPLOY`.

Nenhum código, migration, seeder, cache, worker, `.env` ou configuração foi alterado durante este levantamento.
