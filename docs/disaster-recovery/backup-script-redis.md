# Backup automatizado do Redis — TESTE-DEPLOY

## Escopo atual

`scripts/disaster-recovery/backup-redis.sh` implementa o backup isolado do volume persistente `redis_data`. Ele força a persistência do Redis, interrompe o container de forma controlada, arquiva o volume enquanto o Redis está parado, reinicia o serviço e somente então calcula checksum e transfere o resultado ao destino externo.

Quando executado isoladamente, o script não cria `manifest.sha256` global nem representa backup completo. Por usar um `RUN_ID` próprio, seu diretório promovido é válido apenas para Redis; a execução geral `backup.sh` fornece manifesto, lock, retenção e promoção única.

O fluxo manual continua documentado em [redis-backup-restore.md](redis-backup-restore.md). A implementação foi validada ponta a ponta em execução real isolada; isso não a transforma em backup completo do sistema.

## Variáveis

| Variável | Default de laboratório | Finalidade |
|---|---|---|
| `RUN_ID` | Gerado no formato `YYYY-MM-DD_HHMMSS` | Identificador da execução isolada |
| `REDIS_CONTAINER` | `teste-deploy-redis` | Container Redis em execução |
| `REDIS_VOLUME` | `redis_data` | Volume nomeado que deve estar montado em `/data` |
| `BACKUP_REMOTE_USER` | `teste` | Usuário SSH remoto |
| `BACKUP_REMOTE_HOST` | `172.23.1.115` | Host atual do laboratório, parametrizável em outro ambiente |
| `BACKUP_REMOTE_ROOT` | `/srv/backups/teste-deploy` | Raiz dos backups remotos |
| `BACKUP_SSH_KEY` | `$HOME/.ssh/id_ed25519_backup_lab` | Chave SSH dedicada |

O script valida o formato do nome do container/volume, a existência e o estado em execução do container, a existência do volume e sua montagem como volume nomeado em `/data`. Também identifica a imagem já configurada no container para executar um container auxiliar de archive, sem depender de caminho físico interno do Docker.

## Consistência e janela de indisponibilidade

O volume contém dados AOF em `/data/appendonlydir/` e `dump.rdb`. Para evitar arquivar o conteúdo enquanto o Redis pode escrever, o fluxo é:

1. executar `redis-cli SAVE` dentro de `teste-deploy-redis`;
2. parar o container de forma controlada;
3. executar um container auxiliar com a imagem já usada pelo Redis, `tar` como entrypoint e `--volumes-from <container>:ro`;
4. gerar `redis_data.tar.gz` a partir de `/data` no volume somente-leitura;
5. reiniciar o Redis obrigatoriamente antes de checksum ou transferência remota.

O container auxiliar não inicia outro processo Redis e o volume é exposto a ele somente como leitura. A parada cria uma curta indisponibilidade do Redis; neste laboratório ele não é dependência atual do Laravel, mas esse impacto deve ser reavaliado antes de uso em produção.

## Cleanup e restart obrigatório

O script usa `trap` de saída. Depois de iniciar a parada controlada, o cleanup consulta o estado do container e tenta iniciá-lo se ele estiver parado, inclusive após falha no archive, checksum, SSH, SCP, `chmod` remoto, validação remota ou promoção.

Se `SAVE` falhar, o container não é parado. Se `docker stop` falhar, a saída é falha e o cleanup ainda verifica se o container foi deixado parado. Se o restart falhar, o backup é declarado `FAILED` e não ocorre promoção remota. Depois que o archive/checksum local é válido e o Redis foi reiniciado, falhas remotas preservam o backup local válido e podem preservar `.incomplete` para diagnóstico.

## Resultado local

Para um `RUN_ID` válido, o script cria:

```text
/srv/teste-deploy-data/backup-staging/<RUN_ID>/redis/
├── redis_data.tar.gz
└── redis_data.tar.gz.sha256

/srv/teste-deploy-data/backup-logs/
└── <RUN_ID>-redis.log
```

O archive e o checksum recebem explicitamente modo `600` depois de criados. O checksum é criado com caminho relativo dentro de `redis/`.

## Transferência externa

O fluxo remoto usa os helpers SSH/SCP comuns:

1. falha se o diretório final ou `.incomplete/<RUN_ID>` já existir;
2. cria `<BACKUP_REMOTE_ROOT>/.incomplete/<RUN_ID>/redis/`;
3. transfere `redis_data.tar.gz` e `redis_data.tar.gz.sha256`;
4. aplica `chmod 600` apenas aos dois arquivos transferidos;
5. executa `sha256sum -c redis_data.tar.gz.sha256` no staging remoto;
6. confirma os artefatos esperados e promove `.incomplete/<RUN_ID>` para `<RUN_ID>`.

O diretório promovido será um restore point válido somente para Redis. O script usa chave dedicada, `BatchMode=yes` e `IdentitiesOnly=yes`; não desabilita verificação de host key e não usa `StrictHostKeyChecking=no`.

## Uso conceitual

```bash
scripts/disaster-recovery/backup-redis.sh
```

Um `RUN_ID` pode ser informado para diagnóstico, desde que seja novo e use o formato previsto:

```bash
RUN_ID=2026-09-22_180000 scripts/disaster-recovery/backup-redis.sh
```

## Validação real — 2026-09-22_171547

A execução isolada com `RUN_ID=2026-09-22_171547` terminou com `Backup Redis SUCCESS`.

- `redis-cli SAVE` retornou sucesso antes da parada controlada de `teste-deploy-redis`.
- O archive foi criado por container auxiliar com o volume montado somente-leitura.
- O Redis foi reiniciado com sucesso e voltou ao estado `Up` antes de checksum e transferência externa.
- Após o restart, `DR_TEST_REDIS_001` permaneceu com o valor `disaster-recovery-test`.
- O checksum local e o checksum remoto retornaram `redis_data.tar.gz: SUCESSO`.
- O archive e seu checksum foram transferidos a `.incomplete/2026-09-22_171547/redis`, receberam `chmod 600`, foram validados e promovidos.
- O diretório `.incomplete/2026-09-22_171547` não permaneceu após a promoção.

| Local | Artefato | Modo validado |
|---|---|---|
| Staging local | `redis_data.tar.gz` | `600` |
| Staging local | `redis_data.tar.gz.sha256` | `600` |
| Diretório remoto promovido | `redis_data.tar.gz` | `600` |
| Diretório remoto promovido | `redis_data.tar.gz.sha256` | `600` |

O conteúdo do archive foi inspecionado e continha o layout persistente esperado:

```text
./
./appendonlydir/
./appendonlydir/appendonly.aof.1.base.rdb
./appendonlydir/appendonly.aof.manifest
./appendonlydir/appendonly.aof.1.incr.aof
./dump.rdb
```

A recuperação de `DR_TEST_REDIS_001` em restore isolado já havia sido validada pelo fluxo manual. A execução automatizada confirmou a preservação do marcador após o restart do container original; o restore automatizado continua fora de escopo.

## Limitações pendentes

- Manifesto, lock, retenção e orquestrador existem para a execução geral; a execução isolada não substitui esse fluxo.
- Redis é tratado como estado persistente neste laboratório; em produção a necessidade de backup depende do papel real do serviço.
- O restore manual foi validado em máquina limpa com `DR_TEST_REDIS_001`; restore automatizado permanece pendente.
