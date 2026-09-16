# Secrets e configuração sensível — TESTE-DEPLOY

## Laravel `.env`

| Arquivo | Proprietário/grupo | Permissão | Classificação |
|---|---|---:|---|
| `.env` | `lucas-cooperja:nogroup` | `664` | Configuração sensível da aplicação; contém nomes de secrets e credenciais. |
| `.env.example` | `lucas-cooperja:nogroup` | `664` | Modelo de configuração; deve permanecer sem valores reais. |

As variáveis foram classificadas pelos nomes. A presença de uma variável não confirma que ela possua valor configurado.

| Categoria | Variáveis identificadas |
|---|---|
| Configuração de aplicação | `APP_NAME`, `APP_ENV`, `APP_DEBUG`, `APP_URL`, `APP_LOCALE`, `APP_FALLBACK_LOCALE`, `APP_FAKER_LOCALE`, `APP_MAINTENANCE_DRIVER`, `BCRYPT_ROUNDS`, `VITE_APP_NAME` |
| Chave criptográfica/secret crítico | `APP_KEY` |
| Logs e integrações internas | `LOG_CHANNEL`, `LOG_STACK`, `LOG_DEPRECATIONS_CHANNEL`, `LOG_LEVEL`, `BROADCAST_CONNECTION` |
| Banco de dados | `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` |
| Sessão, cache e fila | `SESSION_DRIVER`, `SESSION_LIFETIME`, `SESSION_ENCRYPT`, `SESSION_PATH`, `SESSION_DOMAIN`, `CACHE_STORE`, `QUEUE_CONNECTION` |
| Redis/Memcached | `REDIS_CLIENT`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`, `MEMCACHED_HOST` |
| E-mail | `MAIL_MAILER`, `MAIL_SCHEME`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME` |
| AWS/cloud | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `AWS_BUCKET`, `AWS_USE_PATH_STYLE_ENDPOINT` |

Variáveis que exigem tratamento como secret ou credencial quando tiverem valor: `APP_KEY`, `DB_PASSWORD`, `REDIS_PASSWORD`, `MAIL_PASSWORD`, `AWS_SECRET_ACCESS_KEY` e, conforme o serviço, `AWS_ACCESS_KEY_ID`, `DB_USERNAME` e `MAIL_USERNAME`.

## Configurações locais da aplicação

| Item | Proprietário/grupo | Permissão | Estado identificado |
|---|---|---:|---|
| `.npmrc` | `lucas-cooperja:nogroup` | `664` | Contém somente as diretivas `ignore-scripts` e `audit`; não foi identificada diretiva de token ou credencial. |
| `auth.json` | — | — | Não identificado no projeto. |
| Arquivos `.pem`, `.key`, `.crt`, `.p12`, `.pfx` | — | — | Não identificados no projeto. |

`.npmrc` não é ignorado pelo `.gitignore` raiz. No estado atual, suas diretivas são configuração não sensível; isso deve ser revalidado antes de eventual versionamento caso o arquivo passe a conter autenticação de registry.

## MySQL

| Item | Proprietário/grupo | Permissão | Categoria e função |
|---|---|---:|---|
| `/etc/mysql/debian.cnf` | `root:root` | `600` | Configuração sensível local, aparentemente destinada à manutenção do MySQL; conteúdo não lido. |
| `laravel@localhost` | — | — | Conta MySQL da aplicação; autenticação não inspecionada. |

Nenhuma senha, hash, plugin de autenticação ou credencial MySQL foi lido ou registrado.

## Nginx e TLS

| Item | Proprietário/grupo | Permissão | Categoria e estado |
|---|---|---:|---|
| `/etc/letsencrypt` | `root:root` | `755` | Estrutura Certbot presente. |
| `/etc/letsencrypt/cli.ini` | `root:root` | `644` | Configuração Certbot; conteúdo não lido. |
| `/etc/letsencrypt/renewal-hooks/*` | `root:root` | `755` | Diretórios de hooks presentes. |
| `/etc/letsencrypt/live`, `archive`, `renewal` | — | — | Não identificados; não há material de certificado emitido encontrado nesse local. |
| `/etc/nginx/snippets/snakeoil.conf` | Arquivo padrão | — | Referência a certificado/chave de exemplo `snakeoil`; não há evidência de uso no virtual host HTTP da aplicação. |

Não foram abertas chaves privadas. O virtual host da aplicação permanece documentado como HTTP na porta 80, sem TLS ativo identificado.

## Docker e Portainer

| Item | Localização | Categoria | Estado identificado |
|---|---|---|---|
| Variáveis do container `portainer` | Metadados do container Docker | Configuração | Apenas `PATH` identificada; nenhuma variável de ambiente sensível foi encontrada. |
| `portainer_data` | `/var/lib/docker/volumes/portainer_data` | Dado persistente potencialmente sensível | Diretório `root:root`, permissão `701`. |
| Dados do volume | `/var/lib/docker/volumes/portainer_data/_data` | Dado persistente potencialmente sensível | Diretório `root:root`, permissão `755`; conteúdo não lido. |
| Socket Docker | `/var/run/docker.sock` | Acesso privilegiado à infraestrutura | Bind mount de leitura e escrita no container Portainer; não é secret de backup. |

## SSH e Git/GitHub

| Item | Localização | Permissão | Estado identificado |
|---|---|---:|---|
| Diretório SSH | `/home/lucas-cooperja/.ssh` | `700` | Existe. |
| Hosts conhecidos | `~/.ssh/known_hosts` | `600` | Arquivo de chaves públicas/fingerprints de hosts conhecidos. |
| Backup de hosts conhecidos | `~/.ssh/known_hosts.old` | `644` | Arquivo de histórico de hosts conhecidos. |
| Chaves privadas SSH | `~/.ssh/id_rsa`, `~/.ssh/id_ed25519` e equivalentes | — | Não identificadas. |
| Git credential helper global | Configuração Git global | — | Não identificado. |
| Armazenamento Git de credenciais | `~/.git-credentials` | — | Não identificado. |
| GitHub CLI | `~/.config/gh` | — | Não identificado. |

## Classificação para reconstrução

| Item | Localização | Categoria | Crítico para reconstrução? | Pode ir para Git? |
|---|---|---|---|---|
| `.env` | Raiz do projeto | Secret/configuração | Sim, sob armazenamento protegido | Não |
| `APP_KEY` | `.env` | Chave criptográfica | Sim, especialmente para dados já criptografados | Não |
| Credenciais de banco | `.env` e MySQL | Credencial/configuração | Sim para conectar à base existente | Não |
| Credenciais AWS, Redis e e-mail | `.env`, se configuradas | Secret/credencial | Somente se os respectivos serviços forem usados | Não |
| `.env.example` | Raiz do projeto | Configuração documentável | Sim, como modelo sem valores reais | Sim, após validação |
| `.npmrc` atual | Raiz do projeto | Configuração | Não crítico | Sim, enquanto não contiver autenticação |
| `/etc/mysql/debian.cnf` | Host | Credencial/configuração sensível | Necessário apenas para administração/manutenção local do MySQL | Não |
| Conta `laravel@localhost` | MySQL | Credencial de aplicação | Sim para acesso à base existente | Não |
| `portainer_data` | Volume Docker | Dado persistente potencialmente sensível | Necessário para preservar estado do Portainer | Não |
| `/var/run/docker.sock` | Host/container Portainer | Acesso privilegiado | Necessário somente se Portainer administrar o Docker local | Não |
| `known_hosts` | `~/.ssh` | Configuração de confiança SSH | Não crítico; reconstruível | Não é necessário |
| Chaves TLS emitidas | Não identificadas | Chave criptográfica/certificado | Não aplicável no estado atual | Não |

## Pendências

- Revalidar permissões de `.env` e `.env.example` caso o grupo `nogroup` não deva ter leitura.
- Reinspecionar `.npmrc` sempre que houver mudança de conteúdo ou adoção de registry autenticado.
- Verificar, somente se necessário, quais dados funcionais e configurações sensíveis estão armazenados em `portainer_data`.
- Revalidar material TLS se certificados forem emitidos ou HTTPS for configurado.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o inventário de secrets, credenciais e configurações sensíveis do ambiente `TESTE-DEPLOY`.

Nenhum valor sensível, senha, token, chave privada, hash ou credencial foi exibido ou modificado durante este levantamento.
