# Backup automatizado local do MySQL — TESTE-DEPLOY

## Escopo atual

`scripts/disaster-recovery/backup-mysql.sh` implementa somente a geração local do dump lógico de `teste_deploy` e de seu checksum SHA-256. Ele não transfere arquivos por SCP, não cria diretório remoto, não produz `manifest.sha256` global, não aplica retenção, não instala Cron e não executa restore.

O fluxo manual validado continua documentado em [mysql-backup-restore.md](mysql-backup-restore.md). Este script é a primeira implementação incremental baseada naquele fluxo.

## Credencial esperada

O script exige a variável de ambiente `MYSQL_BACKUP_DEFAULTS_FILE`, contendo o caminho de um arquivo de opções MySQL já existente, legível somente pelo usuário executor e sem permissões para grupo ou outros. Esse arquivo deve conter as opções de cliente necessárias à autenticação, sem que seus valores sejam colocados no script, na linha de comando, no Git ou nos logs.

O script não lê `.env` da aplicação e não cria nem altera o arquivo de opções. Se a variável não estiver definida, se o caminho não puder ser lido, se o arquivo não pertencer ao usuário executor ou se suas permissões forem amplas, ele falha antes de executar `mysqldump`.

Exemplo conceitual de uso, sem expor valores:

```bash
MYSQL_BACKUP_DEFAULTS_FILE=/caminho/protegido/mysql-backup.cnf \
scripts/disaster-recovery/backup-mysql.sh
```

`RUN_ID` é opcional. Se definido, precisa usar `YYYY-MM-DD_HHMMSS`; caso contrário, o script o gera. `MYSQL_DATABASE` também é opcional e tem como padrão `teste_deploy`; ele aceita somente letras ASCII, números e underscore, com no máximo 64 caracteres. Exemplo conceitual:

```bash
RUN_ID=2026-09-18_230000 \
MYSQL_DATABASE=teste_deploy \
MYSQL_BACKUP_DEFAULTS_FILE=/caminho/protegido/mysql-backup.cnf \
scripts/disaster-recovery/backup-mysql.sh
```

## Resultado local

Para um `RUN_ID` válido, o script cria somente os diretórios necessários e produz:

```text
/srv/teste-deploy-data/backup-staging/<RUN_ID>/mysql/
├── teste_deploy.sql
└── teste_deploy.sql.sha256

/srv/teste-deploy-data/backup-logs/
└── <RUN_ID>-mysql.log
```

O dump preserva as opções manuais já validadas:

- `--single-transaction`;
- `--routines`;
- `--triggers`;
- `--events`;
- `--no-tablespaces`.

O checksum é gerado dentro do diretório `mysql/`, com caminho relativo, equivalente a `sha256sum teste_deploy.sql > teste_deploy.sql.sha256`.

## Segurança e falhas

- O script usa Bash, `set -Eeuo pipefail` e `umask 077`.
- `common.sh` fornece somente helpers compartilháveis de `RUN_ID`, diretórios, logs, dependências, checksum e duração; ele não contém lógica de MySQL.
- As permissões privadas de novos diretórios, logs e artefatos dependem do `umask 077` definido pelo script executor.
- Valida `mysqldump`, `sha256sum`, `stat` e `tee` antes do dump.
- Prepara e valida o log antes de criar o staging específico do `RUN_ID`, evitando diretórios de execução vazios se a infraestrutura de logs falhar.
- O dump é escrito inicialmente em arquivo parcial oculto e somente é promovido ao nome final após sucesso do `mysqldump`.
- Se o dump ou a geração do checksum falhar, somente os artefatos criados pela execução atual são removidos para não parecerem um backup válido; o log de diagnóstico é preservado e o script retorna código diferente de zero. Artefatos preexistentes nunca são removidos por uma tentativa com o mesmo `RUN_ID`.
- O arquivo de log nunca é sobrescrito para evitar misturar duas execuções com o mesmo `RUN_ID`.
- Logs registram etapas, caminhos, valor SHA-256, duração e códigos de saída, mas nunca passwords, conteúdo de `.env`, chaves ou outros secrets.

## Validação real no laboratório

### Sucesso local

O primeiro backup local automatizado validado usou o `RUN_ID` `2026-09-18_172438` e terminou com `Backup MySQL SUCCESS`.

| Item | Resultado validado |
|---|---|
| Autenticação prévia | `CURRENT_USER()` retornou `laravel@localhost` |
| Credencial | Fornecida por `MYSQL_BACKUP_DEFAULTS_FILE`, fora do repositório; o caminho e o conteúdo não são registrados aqui |
| Dump | `/srv/teste-deploy-data/backup-staging/2026-09-18_172438/mysql/teste_deploy.sql` |
| Checksum | `/srv/teste-deploy-data/backup-staging/2026-09-18_172438/mysql/teste_deploy.sql.sha256` |
| Log | `/srv/teste-deploy-data/backup-logs/2026-09-18_172438-mysql.log` |
| Resultado final | `Backup MySQL SUCCESS` |

Isso valida a geração local do dump, do SHA-256 e do log pelo script. Não valida transferência externa, promoção remota, retenção ou restore automatizado.

### Falha proposital e cleanup

Foi executado um teste controlado com `RUN_ID=2026-09-18_173500` e `MYSQL_DATABASE=database_que_nao_existe`.

- `mysqldump` falhou com exit code `2`.
- O script registrou `Backup MySQL FAILED` e retornou exit code `2`.
- O log foi preservado.
- O diretório de staging `/srv/teste-deploy-data/backup-staging/2026-09-18_173500/mysql` permaneceu como evidência, porém vazio.
- Foi confirmado que `teste_deploy.sql`, `teste_deploy.sql.sha256` e `.teste_deploy.sql.partial` não existiam nesse diretório.

O teste confirma que uma falha de dump não deixa artefato parcial parecendo backup válido.

### Preparação de logs

Em duas tentativas anteriores, o diretório `backup-logs` ainda não existia com ownership adequado ao usuário executor. A falha de permissão deixou os diretórios de staging vazios `2026-09-18_172236/mysql` e `2026-09-18_172302/mysql`.

Esses diretórios foram preservados como evidência. O script foi refinado para preparar e validar a infraestrutura de logs antes de criar o staging específico do `RUN_ID`, evitando repetir esse efeito em falhas futuras de preparação de logs.

## Limitações pendentes

- Não há transferência para o destino externo ou promoção por `.incomplete/`.
- Não há `manifest.sha256` da execução completa.
- Não há orquestrador `backup.sh`, lock global, retenção, monitoramento, Cron ou restore automatizado.
- A estratégia de gestão de secrets ainda é provisória; o arquivo de opções precisa ser preparado e protegido fora do repositório.
- O backup em máquina limpa permanece pendente.
