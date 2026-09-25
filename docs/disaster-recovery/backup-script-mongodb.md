# Backup automatizado do MongoDB — TESTE-DEPLOY

## Escopo atual

`scripts/disaster-recovery/backup-mongodb.sh` implementa o backup isolado do banco MongoDB `teste_deploy_lab`: gera um archive dentro do container, copia-o para staging local, calcula SHA-256, transfere para staging remoto `.incomplete`, valida a integridade remotamente e promove o diretório somente depois de sucesso.

Quando executado isoladamente, ele não cria `manifest.sha256` global nem representa backup completo. Por usar um `RUN_ID` próprio, seu diretório promovido é válido somente para MongoDB; a execução geral `backup.sh` fornece manifesto, lock, retenção e promoção única.

O fluxo manual continua documentado em [mongodb-backup-restore.md](mongodb-backup-restore.md). A implementação foi validada ponta a ponta em execução real isolada; isso não a transforma em backup completo do sistema.

## Variáveis

| Variável | Default de laboratório | Finalidade |
|---|---|---|
| `RUN_ID` | Gerado no formato `YYYY-MM-DD_HHMMSS` | Identificador da execução isolada |
| `MONGODB_CONTAINER` | `teste-deploy-mongodb` | Container em execução que contém `mongodump` |
| `MONGODB_DATABASE` | `teste_deploy_lab` | Banco exportado; aceita identificador simples do laboratório |
| `MONGODB_AUTH_DB` | `admin` | Banco de autenticação; aceita identificador simples do laboratório |
| `MONGODB_BACKUP_USER` | `lab_mongo_root` | Usuário de backup; aceita identificador simples do laboratório |
| `MONGODB_BACKUP_PASSWORD_FILE` | Sem default | Arquivo externo protegido que contém somente a senha de backup |
| `BACKUP_REMOTE_USER` | `teste` | Usuário SSH remoto |
| `BACKUP_REMOTE_HOST` | `172.23.1.115` | Host atual do laboratório, parametrizável em outro ambiente |
| `BACKUP_REMOTE_ROOT` | `/srv/backups/teste-deploy` | Raiz dos backups remotos |
| `BACKUP_SSH_KEY` | `$HOME/.ssh/id_ed25519_backup_lab` | Chave SSH dedicada |

Os defaults remotos pertencem apenas ao laboratório atual. O script valida `RUN_ID`, nomes de container e identificadores MongoDB de forma conservadora, além de confirmar que o container existe e está em execução antes do dump.

## Credencial

`MONGODB_BACKUP_PASSWORD_FILE` deve apontar para arquivo já existente, externo ao repositório, legível e pertencente ao usuário executor, sem permissões para grupo ou outros. O script não lê `.env`, não cria nem modifica esse arquivo e não registra seu caminho ou conteúdo.

A senha é lida apenas para uma variável temporária em memória e serializada como scalar YAML com aspas duplas. Barras e aspas duplas são escapadas. Qualquer caractere classificado como controle — inclusive tabulação, quebra de linha e carriage return — é recusado antes de criar o YAML. Caracteres imprimíveis usuais, incluindo espaços, `:`, `#`, `$`, `!`, `@`, aspas e barra invertida, continuam suportados. O YAML é enviado pela entrada padrão de `docker exec -i` para uma configuração temporária no container, criada com `umask 077` em `/tmp/.mongodump-config-<RUN_ID>.yml`.

`mongodump` recebe apenas `--config=<arquivo>`, usuário, banco de autenticação, banco de origem e archive. Ele não recebe `--password`, e a senha não aparece literalmente no script, nos logs, no terminal ou nos argumentos de `mongodump`. As variáveis temporárias do host são removidas logo após a criação da configuração e também pelo cleanup em caso de falha anterior.

## Fluxo local

O script cria:

```text
/srv/teste-deploy-data/backup-staging/<RUN_ID>/mongodb/
├── teste_deploy_lab.archive
└── teste_deploy_lab.archive.sha256

/srv/teste-deploy-data/backup-logs/
└── <RUN_ID>-mongodb.log
```

1. Confirma que nem a configuração `/tmp/.mongodump-config-<RUN_ID>.yml` nem o archive temporário existem no container; colisões falham sem sobrescrever ou remover arquivo preexistente.
2. Cria a configuração YAML temporária por stdin, com permissões privadas no container.
3. Executa `mongodump` com `--config`, usuário, `--authenticationDatabase`, banco e archive temporário sob `/tmp/`.
4. Remove a configuração imediatamente depois de `mongodump`; o cleanup tenta removê-la novamente apenas se ainda pertencer à execução atual.
5. Usa `docker cp` para copiar o archive a um arquivo parcial oculto no staging e remove o archive temporário do container após cópia bem-sucedida.
6. Promove o archive ao nome final apenas após sucesso de `docker cp`.
7. Gera `teste_deploy_lab.archive.sha256` dentro do diretório `mongodb/`, usando caminho relativo.
8. Aplica explicitamente modo `600` ao archive e ao checksum locais.

## Transferência externa

O script reaproveita os helpers SSH/SCP genéricos já utilizados pelo MySQL:

1. falha se o diretório remoto final ou `.incomplete/<RUN_ID>` já existir;
2. cria `<BACKUP_REMOTE_ROOT>/.incomplete/<RUN_ID>/mongodb/`;
3. transfere somente o archive e seu checksum;
4. aplica `chmod 600` remotamente, apenas ao archive e ao checksum em `.incomplete`;
5. executa `sha256sum -c teste_deploy_lab.archive.sha256` remotamente;
6. confirma os dois artefatos em `.incomplete`;
7. promove por `mv` para `<BACKUP_REMOTE_ROOT>/<RUN_ID>`.

O script usa chave dedicada, `BatchMode=yes` e `IdentitiesOnly=yes`; não desabilita verificação de host key nem usa `StrictHostKeyChecking=no`.

## Validação real — 2026-09-22_161037

A execução isolada com `RUN_ID=2026-09-22_161037` terminou com `Backup MongoDB SUCCESS`.

- `mongodump` executou no container `teste-deploy-mongodb` para o banco `teste_deploy_lab`; a coleção `recovery_tests` exportou 1 documento.
- O archive temporário do container foi copiado e promovido para `/srv/teste-deploy-data/backup-staging/2026-09-22_161037/mongodb/teste_deploy_lab.archive`.
- O checksum local foi criado e a validação retornou `teste_deploy_lab.archive: SUCESSO`.
- O archive e seu checksum foram transferidos para `/srv/backups/teste-deploy/.incomplete/2026-09-22_161037/mongodb`.
- O checksum em `.incomplete` retornou sucesso; após a promoção, o diretório final foi `/srv/backups/teste-deploy/2026-09-22_161037` e uma nova validação de checksum também retornou sucesso.
- O diretório `.incomplete/2026-09-22_161037` não permaneceu após a promoção.
- Foi confirmado que a configuração temporária `/tmp/.mongodump-config-2026-09-22_161037.yml` e o archive temporário `/tmp/.teste_deploy_lab.archive.2026-09-22_161037.partial` não permaneceram no container.

A credencial veio de `MONGODB_BACKUP_PASSWORD_FILE`, externo ao repositório. A configuração YAML temporária foi enviada por stdin, usada com `mongodump --config` e removida após o uso; a senha não foi passada em argv nem registrada.

### Hardening de permissões — 2026-09-22_163621

Uma nova execução isolada com `RUN_ID=2026-09-22_163621` terminou com `Backup MongoDB SUCCESS` e validou o hardening comum de permissões.

| Local | Artefato | Modo validado |
|---|---|---|
| Staging local | `teste_deploy_lab.archive` | `600` |
| Staging local | `teste_deploy_lab.archive.sha256` | `600` |
| Diretório remoto promovido | `teste_deploy_lab.archive` | `600` |
| Diretório remoto promovido | `teste_deploy_lab.archive.sha256` | `600` |

O checksum remoto retornou `teste_deploy_lab.archive: SUCESSO`. O diretório `.incomplete/2026-09-22_163621` não permaneceu após a promoção, confirmando a ordem SCP → `chmod 600` remoto → checksum → promoção.

## Cleanup e falhas

- Valida `docker`, `sha256sum`, `stat`, `tee`, `ssh` e `scp` antes de criar o staging MongoDB.
- Se `mongodump`, `docker cp` ou checksum local falhar, remove somente os artefatos e parciais criados pela execução atual, preserva o log e retorna código diferente de zero.
- Configuração e archive temporários do container só recebem flag de cleanup depois que a checagem de colisão confirma sua ausência; eles são removidos em sucesso e pelo cleanup quando uma etapa posterior falha.
- Se a falha ocorrer após o checksum local válido, o archive/checksum local permanecem; uma falha remota não é sucesso e não promove diretório final.
- Se o `chmod 600` remoto falhar, o diretório `.incomplete` e o backup local válido permanecem para diagnóstico; a promoção não ocorre.
- Diretórios `.incomplete` remotos não são removidos automaticamente e não são restore points válidos.
- Artefatos preexistentes em `RUN_ID` repetido não são sobrescritos ou removidos.

## Limitações pendentes

- A validação anterior que observou archive remoto em modo `644` e checksum em `600` foi superada pela execução `2026-09-22_163621`, que confirmou modo `600` para archive e checksum local/remoto.
- Manifesto, lock, retenção e orquestrador existem para a execução geral; a execução isolada não substitui esse fluxo.
- A estratégia de secrets é provisória; o password file não substitui uma política definitiva de gestão/criptografia de secrets.
- O restore manual foi validado em máquina limpa com `DR_TEST_MONGO_001`; restore automatizado permanece pendente.
