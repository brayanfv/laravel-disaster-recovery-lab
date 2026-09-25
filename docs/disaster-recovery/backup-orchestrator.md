# Orquestrador de backup — TESTE-DEPLOY

## Escopo atual

`scripts/disaster-recovery/backup.sh` coordena os cinco backups de componente já existentes em uma única execução. Ele gera ou recebe um único `RUN_ID`, mantém todos os artefatos no mesmo staging local e promove uma única vez o diretório remoto completo.

Esta implementação não instala Cron nem automatiza restore. A execução geral, o lock global e a retenção foram validados no laboratório. Os fluxos isolados dos componentes continuam sendo evidências complementares por componente.

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

Essa validação confirma o fluxo completo de backup orquestrado. O restore automatizado continua fora de escopo, mas a recuperação manual em máquina limpa foi validada posteriormente com o restore point `2026-09-24_173106`.

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

## Lock global

Antes de preparar o staging da execução e antes de qualquer operação remota, `backup.sh` abre `/srv/teste-deploy-data/backup-staging/.backup.lock` e tenta adquirir um `flock -n` exclusivo. O lock é restrito a `backup.sh`; os scripts individuais continuam executáveis de forma isolada, sem `flock`.

Se outra execução geral já mantiver o lock, a nova execução falha rapidamente, registra a indisponibilidade do lock e retorna código diferente de zero. Nesse caso, ela não cria staging remoto, não executa componentes e não promove restore point. O descritor do arquivo é fechado quando o processo termina, liberando o lock.

O mecanismo foi testado de forma efêmera com duas tentativas locais de `flock`; a segunda foi recusada. Ele também foi validado em teste real no laboratório, confirmando que uma segunda execução geral não prossegue enquanto o lock está ocupado.

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

## Retenção

Após uma promoção final bem-sucedida, o orquestrador executa retenção remota. A variável `BACKUP_RETENTION_COUNT` tem default `7` e aceita somente inteiros entre `1` e `365`.

A retenção considera apenas diretórios regulares não simbólicos diretamente em `BACKUP_REMOTE_ROOT` que tenham:

- nome no formato `YYYY-MM-DD_HHMMSS`;
- `manifest.sha256` regular, não simbólico.

Os candidatos são ordenados pelo nome do `RUN_ID`; os sete mais recentes são preservados por padrão e somente os excedentes mais antigos são removidos por caminho explícito validado. `.incomplete/`, arquivos soltos, links simbólicos, nomes inválidos e diretórios sem manifesto não participam da seleção e não são removidos. O script nunca remove staging local.

A retenção só é chamada depois de todos os componentes, manifesto, checksum remoto e promoção terem sido concluídos. Se ela falhar, o novo restore point promovido continua válido: o orquestrador registra um aviso e termina o fluxo de backup sem declarar a promoção inválida.

As validações reais concluídas foram:

- no `RUN_ID` `2026-09-24_165238`, a retenção não destrutiva no destino real registrou `RETENTION_RESTORE_POINTS=2`, `RETENTION_KEEP_COUNT=7` e `RETENTION_STATUS=SUCCESS`;
- em `/srv/backups/teste-deploy-retention-test`, uma raiz remota isolada e distinta dos backups reais, o helper `dr_remote_apply_retention` recebeu nove restore points fictícios válidos e `keep_count=7`;
- o helper removeu somente `2026-01-01_010101` e `2026-01-02_010101`, preservou `2026-01-03_010101` até `2026-01-09_010101`, e também preservou `.incomplete/`, `nome-invalido/`, `2026-01-10_010101-sem-manifest/` e `um-arquivo-solto`.

Esse teste destrutivo foi limitado à raiz isolada; `/srv/backups/teste-deploy` não foi usado como alvo de remoção. A raiz de teste foi preservada após a evidência, pois sua remoção exige intervenção administrativa manual.

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

- O wrapper de Cron e a entrada diária de backup já existem e foram validados manualmente; a primeira execução diária pelo daemon continua pendente.
- Definir monitoramento, estratégia definitiva de secrets e restore automatizado separadamente.
- Formalizar o reprovisionamento do pipeline de backup em host com usuário, caminhos e secrets diferentes.
