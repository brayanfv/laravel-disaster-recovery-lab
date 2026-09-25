# Backup automatizado local do MySQL — TESTE-DEPLOY

## Escopo atual

`scripts/disaster-recovery/backup-mysql.sh` implementa a geração local do dump lógico de `teste_deploy`, seu checksum SHA-256 e a transferência automatizada desses dois artefatos para o destino externo do laboratório. A transferência usa staging remoto `.incomplete`, valida o checksum remotamente e só promove a execução após sucesso.

Quando executado isoladamente, ele não produz o `manifest.sha256` global nem promove um restore point completo. Na execução geral, `backup.sh` fornece o manifesto, o lock, a retenção e a promoção única; o wrapper de Cron existe e foi validado manualmente.

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

Após a promoção local do dump e a criação do checksum, o helper comum aplica explicitamente modo `600` a `teste_deploy.sql` e `teste_deploy.sql.sha256`. Assim, ambos devem terminar privados independentemente da criação inicial sob `umask 077`.

A mesma política é implementada no MySQL e no MongoDB. A validação real do hardening foi executada com o fluxo MongoDB em `2026-09-22_163621`; uma execução MySQL específica com essa alteração de permissões ainda não foi realizada.

## Transferência externa automatizada

Os parâmetros remotos são variáveis de ambiente com defaults exclusivos do laboratório atual:

| Variável | Default de laboratório | Finalidade |
|---|---|---|
| `BACKUP_REMOTE_USER` | `teste` | Usuário SSH remoto |
| `BACKUP_REMOTE_HOST` | `172.23.1.115` | Host atual do laboratório; deve ser parametrizado em outro ambiente |
| `BACKUP_REMOTE_ROOT` | `/srv/backups/teste-deploy` | Raiz dos backups remotos |
| `BACKUP_SSH_KEY` | `$HOME/.ssh/id_ed25519_backup_lab` | Chave SSH dedicada ao laboratório |

Os defaults não são requisito definitivo de produção. O script valida formatos conservadores para usuário, host e raiz remota e confirma que a chave informada é legível. Ele usa explicitamente a chave dedicada, `BatchMode=yes` e `IdentitiesOnly=yes`; não desabilita a verificação de host key e não usa `StrictHostKeyChecking=no`.

Após criar e validar o dump/checksum local, o fluxo remoto proposto pelo script é:

1. falhar se `/srv/backups/teste-deploy/<RUN_ID>` já existir;
2. falhar se `/srv/backups/teste-deploy/.incomplete/<RUN_ID>` já existir;
3. criar `/srv/backups/teste-deploy/.incomplete/<RUN_ID>/mysql/`;
4. transferir somente `teste_deploy.sql` e `teste_deploy.sql.sha256` por SCP;
5. aplicar `chmod 600` remotamente, apenas nesses dois arquivos em `.incomplete`;
6. executar `sha256sum -c teste_deploy.sql.sha256` no diretório remoto `mysql/`;
7. confirmar, ainda em `.incomplete`, a existência de todos os artefatos esperados;
8. promover por `mv`, no destino remoto, de `.incomplete/<RUN_ID>` para `<RUN_ID>`; se o `mv` retornar sucesso, a promoção é concluída.

Somente o diretório promovido em `BACKUP_REMOTE_ROOT/<RUN_ID>` será um backup remoto válido. Se o `mv` falhar, a promoção falha e o diretório `.incomplete` permanece para diagnóstico; ele não é restore point válido. Em falha durante preparação, SCP ou checksum remoto, a promoção também não ocorre. O dump local já validado pode permanecer nessas situações.

## Segurança e falhas

- O script usa Bash, `set -Eeuo pipefail` e `umask 077`.
- `common.sh` fornece somente helpers compartilháveis de `RUN_ID`, diretórios, logs, dependências, checksum e duração; ele não contém lógica de MySQL.
- Os helpers de SSH/SCP, criação de staging remoto, verificação remota de checksum e promoção recebem parâmetros genéricos; nomes de banco e artefatos MySQL permanecem em `backup-mysql.sh`.
- As permissões privadas de novos diretórios e logs dependem do `umask 077` definido pelo script executor. Para artefatos, o helper comum aplica explicitamente `chmod 600` ao dump/checksum local e, após SCP, ao dump/checksum remoto antes da validação e promoção.
- Valida `mysqldump`, `sha256sum`, `stat`, `tee`, `chmod`, `ssh` e `scp` antes do dump.
- Prepara e valida o log antes de criar o staging específico do `RUN_ID`, evitando diretórios de execução vazios se a infraestrutura de logs falhar.
- O dump é escrito inicialmente em arquivo parcial oculto e somente é promovido ao nome final após sucesso do `mysqldump`.
- Se o dump ou a geração do checksum falhar, somente os artefatos criados pela execução atual são removidos para não parecerem um backup válido; o log de diagnóstico é preservado e o script retorna código diferente de zero. Artefatos preexistentes nunca são removidos por uma tentativa com o mesmo `RUN_ID`.
- O arquivo de log nunca é sobrescrito para evitar misturar duas execuções com o mesmo `RUN_ID`.
- Logs registram etapas, caminhos, valor SHA-256, duração e códigos de saída, mas nunca passwords, conteúdo de `.env`, chaves ou outros secrets.
- O resultado `SUCCESS` só pode ser registrado depois do dump/checksum local, transferência, checksum remoto e promoção remota bem-sucedidos.
- Se o `chmod 600` remoto falhar, o script retorna falha sem promover; o diretório `.incomplete` e o backup local válido permanecem para diagnóstico.

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

Isso valida a geração local inicial. A transferência externa, a promoção remota e a integração com manifesto, lock e retenção foram validadas posteriormente pelo script e pelo orquestrador.

### Falha real de conectividade externa

Uma execução com `RUN_ID` `2026-09-22_135938` alcançou com sucesso o backup local, mas falhou durante a preparação remota porque a máquina externa estava inacessível/desligada.

- O SSH retornou `No route to host` para a porta 22 do host remoto.
- O backup local já criado foi preservado.
- A preparação remota falhou e nenhuma promoção remota foi declarada.
- O script registrou `Backup MySQL FAILED` e retornou exit code `255`.

Depois que a máquina externa voltou, conectividade por ping e SSH com a chave dedicada foram confirmadas antes da nova execução completa. Esse resultado valida o comportamento *fail-fast* remoto: indisponibilidade externa não é convertida em sucesso local nem em restore point remoto válido.

### Sucesso completo com transferência externa

A execução completa com `RUN_ID` `2026-09-22_140816` terminou com `Backup MySQL SUCCESS`.

| Etapa | Resultado validado |
|---|---|
| Staging remoto | `.incomplete/2026-09-22_140816/mysql` criado no destino externo |
| Transferência | `teste_deploy.sql` e `teste_deploy.sql.sha256` enviados |
| Integridade remota | `sha256sum -c teste_deploy.sql.sha256` retornou `teste_deploy.sql: SUCESSO` |
| Promoção | `.incomplete/2026-09-22_140816` promovido para `2026-09-22_140816` |
| Limpeza lógica | O diretório `.incomplete/2026-09-22_140816` deixou de existir após o `mv` bem-sucedido |
| Validação final | O checksum foi executado novamente no diretório promovido e retornou `teste_deploy.sql: SUCESSO` |

Os artefatos remotos finais são:

```text
/srv/backups/teste-deploy/2026-09-22_140816/mysql/teste_deploy.sql
/srv/backups/teste-deploy/2026-09-22_140816/mysql/teste_deploy.sql.sha256
```

Essa validação confirma o fluxo automatizado MySQL de dump/checksum local, staging remoto `.incomplete`, SCP, checksum remoto, promoção e validação final no diretório promovido. O diretório final é um restore point válido para esse componente; ele não representa ainda um backup completo do sistema.

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

- O manifesto, orquestrador, lock e retenção existem para a execução geral; a execução isolada não substitui esse fluxo completo.
- O wrapper de Cron existe e foi validado manualmente; a execução diária do **backup** pelo daemon permanece pendente.
- A estratégia de gestão de secrets ainda é provisória; o arquivo de opções precisa ser preparado e protegido fora do repositório.
- O restore manual de MySQL foi validado em máquina limpa com o restore point `2026-09-24_173106`; restore automatizado permanece pendente.
