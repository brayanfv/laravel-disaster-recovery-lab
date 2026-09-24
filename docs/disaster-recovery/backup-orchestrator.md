# Orquestrador de backup — TESTE-DEPLOY

## Escopo atual

`scripts/disaster-recovery/backup.sh` coordena os cinco backups de componente já existentes em uma única execução. Ele gera ou recebe um único `RUN_ID`, mantém todos os artefatos no mesmo staging local e promove uma única vez o diretório remoto completo.

Esta implementação não instala Cron, não aplica retenção, não cria lock e não automatiza restore. A execução geral foi validada no laboratório; os fluxos isolados dos componentes continuam sendo evidências complementares por componente.

## Modos de execução

### Isolado

Quando executado diretamente, cada `backup-<componente>.sh` continua com o contrato já existente:

- `RUN_ID` pode ser gerado pelo próprio script;
- o script cria o staging remoto `.incomplete/<RUN_ID>/<componente>/`;
- transfere, aplica modo `600`, valida o checksum do componente e promove sozinho o diretório `<RUN_ID>`;
- o diretório promovido vale somente como restore point isolado daquele componente.

### Orquestrado

`backup.sh` inicia os componentes com `DR_ORCHESTRATED=1` e repassa o mesmo `RUN_ID` para todos. Nesse modo, o `RUN_ID` é obrigatório nos scripts de componente.

Cada componente cria somente seu subdiretório remoto, transfere o archive e checksum, aplica modo `600` e valida o checksum remoto. Ele não promove `.incomplete/<RUN_ID>`.

O valor `DR_ORCHESTRATED` aceita apenas `0` ou `1`. O orquestrador deve ser iniciado sem esse modo ativo; ele o define apenas para os processos-filhos.

### Falha inicial de encaminhamento — `2026-09-24_142240`

O primeiro teste do orquestrador preparou com sucesso o staging remoto único para o `RUN_ID` `2026-09-24_142240`, mas falhou antes de iniciar o backup MySQL. O orquestrador havia definido `RUN_ID` como somente leitura e tentou encaminhá-lo ao processo-filho por uma atribuição temporária no shell atual. O Bash recusou essa atribuição por se tratar de variável readonly.

Nenhum componente de backup foi executado, não houve promoção e o diretório `.incomplete/<RUN_ID>` foi preservado para diagnóstico. A correção preserva `RUN_ID` como readonly no orquestrador e usa `env DR_ORCHESTRATED=1 RUN_ID="$RUN_ID" <script>` para definir as variáveis somente no ambiente do processo-filho.

Esse teste registrou apenas a falha de encaminhamento. A execução geral posterior validou o manifesto e a promoção única.

### Execução geral bem-sucedida — `2026-09-24_142925`

O `RUN_ID` único `2026-09-24_142925` terminou com `Backup geral SUCCESS`. MySQL, MongoDB, Redis, Laravel storage e Portainer foram executados sequencialmente em modo orquestrado e concluíram com sucesso. Os componentes criaram e validaram seus subdiretórios, mas não promoveram individualmente a execução.

No staging local, todos os artefatos, checksums e `manifest.sha256` estavam em modo `600`. O manifesto continha hashes relativos para:

```text
mysql/teste_deploy.sql
mongodb/teste_deploy_lab.archive
redis/redis_data.tar.gz
laravel-storage/laravel-storage.tar.gz
portainer/portainer_data.tar.gz
```

`sha256sum -c manifest.sha256` validou com sucesso os cinco artefatos localmente e, após a transferência, no staging remoto. No destino externo, todos os artefatos, checksums e o manifesto também estavam em modo `600`.

Depois da validação remota do manifesto, ocorreu uma única promoção para `/srv/backups/teste-deploy/2026-09-24_142925`. O diretório `.incomplete/2026-09-24_142925` não existia após o `mv` bem-sucedido. Redis e Portainer voltaram ao estado `Up`, e o marcador `DR_TEST_REDIS_001` permaneceu válido.

Essa validação confirma o fluxo completo de backup orquestrado, não um restore automatizado ou a recuperação em máquina limpa.

## Estrutura da execução

Staging local:

```text
/srv/teste-deploy-data/backup-staging/<RUN_ID>/
├── mysql/teste_deploy.sql
├── mongodb/teste_deploy_lab.archive
├── redis/redis_data.tar.gz
├── laravel-storage/laravel-storage.tar.gz
├── portainer/portainer_data.tar.gz
└── manifest.sha256
```

Durante a execução, o destino externo contém somente o staging não válido:

```text
/srv/backups/teste-deploy/.incomplete/<RUN_ID>/
├── mysql/
├── mongodb/
├── redis/
├── laravel-storage/
├── portainer/
└── manifest.sha256
```

Após validação global e promoção, o diretório passa para:

```text
/srv/backups/teste-deploy/<RUN_ID>/
```

Somente o diretório promovido é um restore point completo potencial. Tudo sob `.incomplete/` serve exclusivamente para diagnóstico e não deve participar de restore ou retenção.

## Ordem e preparação remota

Antes de executar qualquer componente, `backup.sh`:

1. resolve e valida o `RUN_ID` no formato `YYYY-MM-DD_HHMMSS`;
2. falha se o staging local desse identificador já existir;
3. falha se o diretório remoto final ou o remoto incompleto já existir;
4. cria uma única vez `/srv/backups/teste-deploy/.incomplete/<RUN_ID>/`.

Os componentes são chamados sequencialmente, nesta ordem:

1. MySQL;
2. MongoDB;
3. Redis;
4. Laravel storage;
5. Portainer.

Não há paralelismo. Isso preserva as janelas controladas já usadas individualmente por Redis e Portainer.

## Manifesto global e promoção

Depois que os cinco componentes retornam sucesso, o orquestrador cria no staging local `manifest.sha256` com SHA-256 somente dos artefatos finais, usando caminhos relativos à raiz da execução:

```text
<hash>  mysql/teste_deploy.sql
<hash>  mongodb/teste_deploy_lab.archive
<hash>  redis/redis_data.tar.gz
<hash>  laravel-storage/laravel-storage.tar.gz
<hash>  portainer/portainer_data.tar.gz
```

O manifesto não inclui os arquivos individuais `.sha256`. Ele recebe modo `600`, é transferido para o diretório remoto `.incomplete`, também recebe modo `600` e é validado remotamente com `sha256sum -c manifest.sha256` a partir da raiz da execução.

Somente depois dessa validação o orquestrador confirma a presença de todos os artifacts, checksums individuais e manifesto esperados e executa o único `mv` remoto de `.incomplete/<RUN_ID>` para `<RUN_ID>`.

## Falhas

O fluxo é *fail-fast*:

- se um componente falhar, os seguintes não são executados;
- não há criação, transferência ou promoção do manifesto;
- o diretório remoto `.incomplete/<RUN_ID>` é preservado para diagnóstico;
- artefatos locais já validados permanecem disponíveis;
- Redis e Portainer mantêm seus próprios `trap`/cleanup para que uma falha interna não os deixe parados.

Uma execução que falhar não é um restore point válido, mesmo que alguns componentes tenham sido transferidos com sucesso.

## Uso conceitual

O processo requer que as credenciais externas já exigidas pelos scripts de MySQL e MongoDB estejam disponíveis ao ambiente do executor, sem inserir seus valores em comandos, logs ou Git:

```bash
MYSQL_BACKUP_DEFAULTS_FILE=/caminho/protegido/mysql-backup.cnf \
MONGODB_BACKUP_PASSWORD_FILE=/caminho/protegido/mongodb-backup-password \
scripts/disaster-recovery/backup.sh
```

`RUN_ID` pode ser fornecido para diagnóstico, desde que seja novo e válido:

```bash
RUN_ID=2026-09-24_150000 \
MYSQL_BACKUP_DEFAULTS_FILE=/caminho/protegido/mysql-backup.cnf \
MONGODB_BACKUP_PASSWORD_FILE=/caminho/protegido/mongodb-backup-password \
scripts/disaster-recovery/backup.sh
```

Os valores e os caminhos reais das credenciais não devem ser registrados no repositório.

## Pendências

- Implementar lock global, retenção e agendamento somente em incrementos posteriores.
- Definir monitoramento, estratégia definitiva de secrets e restore automatizado separadamente.
- Validar a recuperação completa em máquina limpa.
