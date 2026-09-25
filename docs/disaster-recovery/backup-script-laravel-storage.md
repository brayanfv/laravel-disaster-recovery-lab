# Backup automatizado do Laravel storage — TESTE-DEPLOY

## Escopo atual

`scripts/disaster-recovery/backup-laravel-storage.sh` implementa o backup isolado do conteúdo persistente de `storage/app/private/` do projeto Laravel. Ele cria archive local, checksum SHA-256, transfere ambos por SSH/SCP para staging remoto `.incomplete`, valida a integridade remotamente e promove o diretório somente após sucesso.

Quando executado isoladamente, o script não cria `manifest.sha256` global nem representa backup completo. Por usar um `RUN_ID` próprio, seu diretório promovido é válido apenas para Laravel storage; a execução geral `backup.sh` fornece manifesto, lock, retenção e promoção única.

O restore manual continua documentado em [laravel-storage-backup-restore.md](laravel-storage-backup-restore.md). A implementação foi validada ponta a ponta em execução real isolada; isso não a transforma em backup completo do sistema.

## Variáveis

| Variável | Default de laboratório | Finalidade |
|---|---|---|
| `RUN_ID` | Gerado no formato `YYYY-MM-DD_HHMMSS` | Identificador da execução isolada |
| `LARAVEL_PROJECT_ROOT` | `/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy` | Raiz do projeto Laravel |
| `BACKUP_REMOTE_USER` | `teste` | Usuário SSH remoto |
| `BACKUP_REMOTE_HOST` | `172.23.1.115` | Host atual do laboratório, parametrizável em outro ambiente |
| `BACKUP_REMOTE_ROOT` | `/srv/backups/teste-deploy` | Raiz dos backups remotos |
| `BACKUP_SSH_KEY` | `$HOME/.ssh/id_ed25519_backup_lab` | Chave SSH dedicada |

## Fonte e conteúdo

A única origem é:

```text
<LARAVEL_PROJECT_ROOT>/storage/app/private/
```

O comando usado é:

```bash
tar -czf <arquivo-parcial> -C <LARAVEL_PROJECT_ROOT>/storage/app/private .
```

O archive contém os caminhos relativos a `storage/app/private/`, iniciando em `./`; ele não contém caminhos absolutos. Como o escopo é somente esse diretório, ficam fora do archive `vendor/`, `node_modules/`, `.git/`, `storage/logs/`, caches, arquivos temporários e qualquer outro diretório externo ao storage privado. Arquivos presentes dentro de `storage/app/private/` são tratados como dados persistentes do escopo, inclusive o marcador `DR_TEST_STORAGE_001.txt`.

## Janela de consistência

Este é um backup por filesystem. Laravel, Nginx e Cron não são parados. Portanto, um arquivo modificado exatamente durante a criação do tar pode refletir uma janela de consistência. O script não cria nem pressupõe snapshot de filesystem; a necessidade de consistência mais forte deve ser avaliada conforme a natureza dos uploads/dados em produção.

## Resultado local

Para um `RUN_ID` válido, o script cria:

```text
/srv/teste-deploy-data/backup-staging/<RUN_ID>/laravel-storage/
├── laravel-storage.tar.gz
└── laravel-storage.tar.gz.sha256

/srv/teste-deploy-data/backup-logs/
└── <RUN_ID>-laravel-storage.log
```

O archive é criado inicialmente como arquivo parcial oculto e somente promovido ao nome final após sucesso do `tar`. O archive e o checksum recebem explicitamente modo `600`. O checksum é gerado com caminho relativo dentro de `laravel-storage/`.

## Transferência externa

O fluxo remoto usa os helpers SSH/SCP comuns:

1. falha se o diretório final ou `.incomplete/<RUN_ID>` já existir;
2. cria `<BACKUP_REMOTE_ROOT>/.incomplete/<RUN_ID>/laravel-storage/`;
3. transfere `laravel-storage.tar.gz` e `laravel-storage.tar.gz.sha256`;
4. aplica `chmod 600` somente aos dois arquivos transferidos;
5. executa `sha256sum -c laravel-storage.tar.gz.sha256` no staging remoto;
6. confirma os artefatos esperados e promove `.incomplete/<RUN_ID>` para `<RUN_ID>`.

Se uma etapa remota falhar, o archive/checksum local válidos permanecem, o diretório `.incomplete` pode ser preservado para diagnóstico e não há promoção. O script usa chave dedicada, `BatchMode=yes` e `IdentitiesOnly=yes`; não desabilita verificação de host key e não usa `StrictHostKeyChecking=no`.

## Falhas locais

Se `tar` ou a criação do checksum falhar, o cleanup remove somente os artefatos parciais ou finais criados pela execução atual antes de se tornarem válidos. Artefatos existentes de outro `RUN_ID` não são sobrescritos ou removidos. Logs de diagnóstico são preservados.

## Uso conceitual

```bash
scripts/disaster-recovery/backup-laravel-storage.sh
```

Exemplo com `RUN_ID` de diagnóstico novo:

```bash
RUN_ID=2026-09-22_180000 scripts/disaster-recovery/backup-laravel-storage.sh
```

## Validação real — 2026-09-22_172710

A execução isolada com `RUN_ID=2026-09-22_172710` terminou com sucesso para a fonte `storage/app/private/`.

- `DR_TEST_STORAGE_001.txt` foi confirmado antes do backup.
- O archive foi criado com estrutura relativa, sem caminhos absolutos.
- O checksum local e o checksum remoto foram validados com sucesso.
- Archive e checksum receberam modo `600` tanto no staging local quanto no diretório remoto promovido.
- A transferência, a promoção e a remoção lógica de `.incomplete/2026-09-22_172710` foram concluídas.

O conteúdo validado no archive foi:

```text
./
./.gitignore
./scheduler-dr-test.log
./DR_TEST_STORAGE_001.txt
```

O restore isolado em `/tmp/laravel-storage-restore-test` recuperou `DR_TEST_STORAGE_001.txt` com o conteúdo esperado, além de `.gitignore` e `scheduler-dr-test.log`.

### Observação operacional de restore

As permissões recuperadas são as que estavam armazenadas no archive. Na extração isolada foram observados `DR_TEST_STORAGE_001.txt` e `scheduler-dr-test.log` em modo `664`, e `.gitignore` em modo `775`. Isso não foi tratado como falha do backup. O runbook de restore deverá validar e, quando necessário, ajustar permissões e ownership para o usuário e o serviço da máquina de destino.

## Limitações pendentes

- Manifesto, lock, retenção e orquestrador existem para a execução geral; a execução isolada não substitui esse fluxo.
- A consistência é por filesystem e não há snapshot; arquivos modificados durante a criação do archive exigem avaliação de risco conforme a produção.
- O restore no caminho definitivo foi validado em máquina limpa com `DR_TEST_STORAGE_001.txt` e `scheduler-dr-test.log`; ownership e permissões devem continuar sendo revisados em cada host alvo.
