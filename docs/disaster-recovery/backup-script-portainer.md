# Backup automatizado do Portainer — TESTE-DEPLOY

## Escopo atual

`scripts/disaster-recovery/backup-portainer.sh` implementa o backup isolado do volume persistente `portainer_data`. Ele interrompe o container `portainer`, arquiva o volume enquanto o serviço está parado, reinicia o container e somente então calcula checksum e transfere o resultado ao destino externo.

O script não cria `manifest.sha256` global, não executa retenção, lock global, Cron, restore ou orquestração completa. Por usar um `RUN_ID` próprio, um diretório promovido por este script é restore point válido apenas para o componente Portainer; ele não representa backup completo do sistema nem deve ser combinado com diretórios finais já promovidos por outros scripts de componente.

O fluxo manual continua documentado em [portainer-backup-restore.md](portainer-backup-restore.md). A implementação automatizada isolada foi validada ponta a ponta no laboratório; ela ainda não representa um backup completo de todos os componentes do sistema.

## Variáveis

| Variável | Default de laboratório | Finalidade |
|---|---|---|
| `RUN_ID` | Gerado no formato `YYYY-MM-DD_HHMMSS` | Identificador da execução isolada |
| `PORTAINER_CONTAINER` | `portainer` | Container Portainer em execução |
| `PORTAINER_VOLUME` | `portainer_data` | Volume nomeado que deve estar montado em `/data` |
| `BACKUP_REMOTE_USER` | `teste` | Usuário SSH remoto |
| `BACKUP_REMOTE_HOST` | `172.23.1.115` | Host atual do laboratório, parametrizável em outro ambiente |
| `BACKUP_REMOTE_ROOT` | `/srv/backups/teste-deploy` | Raiz dos backups remotos |
| `BACKUP_SSH_KEY` | `$HOME/.ssh/id_ed25519_backup_lab` | Chave SSH dedicada |

## Consistência e indisponibilidade temporária

O backup usa uma curta janela de indisponibilidade para impedir escrita no volume durante o archive:

1. parar `portainer` de forma controlada;
2. montar explicitamente apenas `portainer_data` em `/data` como somente-leitura em container auxiliar;
3. executar somente `tar` no container auxiliar para gerar `portainer_data.tar.gz`;
4. reiniciar o Portainer obrigatoriamente antes de checksum ou transferência remota.

O container auxiliar usa `alpine:3.20`, imagem pequena com tag fixa; sua base BusyBox inclui o applet `tar`. A imagem é validada localmente antes da parada do Portainer, para não iniciar download durante a janela de indisponibilidade. O container auxiliar não inicia outro processo Portainer. O socket Docker não é montado nele nem entra no archive; ele é dependência de runtime, não dado persistente de backup.

### Falha observada e correção

A execução `2026-09-24_133313` parou o Portainer corretamente, mas falhou ao criar o archive porque a imagem original do Portainer usada como auxiliar não continha o executável `tar`; Docker retornou exit code `127` com `exec: "tar": executable file not found in $PATH`.

O cleanup foi acionado e reiniciou o Portainer com sucesso. O backup terminou como `FAILED` e nenhum restore point remoto válido foi promovido. A correção substitui a imagem auxiliar derivada da imagem do Portainer por `alpine:3.20`, mantendo a montagem explícita e somente-leitura de `portainer_data` em `/data`.

## Cleanup e restart obrigatório

O script usa `trap` de saída. Depois de iniciar a parada controlada, o cleanup consulta o estado do container e tenta iniciá-lo se ele estiver parado, inclusive após falha no archive, checksum, SSH, SCP, `chmod` remoto, validação remota ou promoção.

Se `docker stop` falhar, a saída é falha e o cleanup ainda verifica se o container foi deixado parado. Se o restart falhar, o backup é declarado `FAILED` e não ocorre promoção remota. Depois que o archive/checksum local é válido e o Portainer foi reiniciado, falhas remotas preservam o backup local válido e podem preservar `.incomplete` para diagnóstico.

## Resultado local

Para um `RUN_ID` válido, o script cria:

```text
/srv/teste-deploy-data/backup-staging/<RUN_ID>/portainer/
├── portainer_data.tar.gz
└── portainer_data.tar.gz.sha256

/srv/teste-deploy-data/backup-logs/
└── <RUN_ID>-portainer.log
```

O archive é criado inicialmente como arquivo parcial oculto e somente promovido ao nome final após sucesso do `tar`. O archive e o checksum recebem explicitamente modo `600`. O checksum é gerado com caminho relativo dentro de `portainer/`.

## Transferência externa

O fluxo remoto usa os helpers SSH/SCP comuns:

1. falha se o diretório final ou `.incomplete/<RUN_ID>` já existir;
2. cria `<BACKUP_REMOTE_ROOT>/.incomplete/<RUN_ID>/portainer/`;
3. transfere `portainer_data.tar.gz` e `portainer_data.tar.gz.sha256`;
4. aplica `chmod 600` somente aos dois arquivos transferidos;
5. executa `sha256sum -c portainer_data.tar.gz.sha256` no staging remoto;
6. confirma os artefatos esperados e promove `.incomplete/<RUN_ID>` para `<RUN_ID>`.

Se uma etapa remota falhar, o archive/checksum local válidos permanecem, o diretório `.incomplete` pode ser preservado para diagnóstico e não há promoção. O script usa chave dedicada, `BatchMode=yes` e `IdentitiesOnly=yes`; não desabilita verificação de host key e não usa `StrictHostKeyChecking=no`.

## Imagem do Portainer

O container usa atualmente `portainer/portainer-ce:latest`. Essa tag mutável continua sendo um gap: antes de um disaster recovery final em máquina limpa, a imagem deverá ser fixada por versão ou digest. Esta tarefa não altera a imagem.

## Uso conceitual

```bash
scripts/disaster-recovery/backup-portainer.sh
```

Exemplo com `RUN_ID` de diagnóstico novo:

```bash
RUN_ID=2026-09-22_180000 scripts/disaster-recovery/backup-portainer.sh
```

## Validação real — `2026-09-24_134725`

Uma execução isolada concluiu com `Backup Portainer SUCCESS`.

- A imagem auxiliar `alpine:3.20` estava disponível e continha `tar`.
- O container `portainer` foi parado de forma controlada; `portainer_data` foi montado em `/data:ro` no container auxiliar, sem montar `docker.sock`.
- O archive foi criado, o Portainer foi reiniciado e voltou ao estado `Up`.
- O checksum local foi criado e validado; o archive e o checksum locais ficaram com modo `600`.
- A transferência externa foi concluída, os dois arquivos remotos receberam modo `600` e o checksum remoto foi validado antes da promoção.
- O diretório remoto foi promovido de `.incomplete/2026-09-24_134725` para o restore point final; o diretório incompleto deixou de existir após a promoção.

O archive observado continha a estrutura persistente esperada:

```text
./
./certs/
./certs/cert.pem
./certs/key.pem
./bin/
./tls/
./portainer.pub
./portainer.key
./portainer.db
./compose/
./chisel/
./chisel/private-key.pem
```

Os nomes registram apenas a estrutura; nenhum conteúdo sensível foi incluído nesta documentação.

### Restore isolado

O archive promovido foi extraído em `/tmp/portainer-restore-test`, sem sobrescrever o volume original. `portainer.db` foi recuperado. Os arquivos sensíveis observados — `portainer.db`, `portainer.key`, `certs/key.pem` e `chisel/private-key.pem` — permaneceram com modo restritivo `600` após a extração.

Essa validação confirma a recuperação do conteúdo do volume em diretório isolado. A validação de restore em uma máquina limpa e a automação de restore continuam pendentes.

## Limitações pendentes

- A execução real validou o caminho de sucesso. A falha de criação do archive no `RUN_ID` `2026-09-24_133313` também validou o `trap` de cleanup e o reinício obrigatório do Portainer; outros tipos de falha ainda não foram injetados individualmente.
- Não há `manifest.sha256` global, retenção, lock global, Cron, monitoramento, orquestrador ou restore automatizado.
- A tag `portainer/portainer-ce:latest` continua mutável e não é adequada para reconstrução final reproduzível.
- Backup e restore em máquina limpa continuam pendentes.
