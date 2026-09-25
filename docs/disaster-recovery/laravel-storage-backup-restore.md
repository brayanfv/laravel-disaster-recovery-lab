# Backup e restore manual do Laravel storage — TESTE-DEPLOY

## Objetivo

Registrar o fluxo manual de backup e restore validado para o storage privado persistente da aplicação Laravel.

O fluxo validou o archive de `storage/app/private`, transferência ao destino externo, verificações SHA-256, extração em diretório isolado e recuperação do marcador de storage e do log do Scheduler.

## Pré-requisitos e origem

| Item | Estado confirmado |
|---|---|
| Origem persistente | `storage/app/private` |
| Staging local | `/srv/teste-deploy-data/backup-staging/laravel-storage` |
| Artefato | `laravel-private-storage.tar.gz` |
| Destino externo | `teste@172.23.1.115:/srv/backups/teste-deploy/` |
| Diretório de restore isolado | `/tmp/laravel-storage-restore-test` |

O conteúdo de `storage/app/private` é ignorado pelo Git e não pode ser reconstruído apenas por clone do repositório.

Marcadores presentes na origem:

- `DR_TEST_STORAGE_001.txt`, com o conteúdo de teste de disaster recovery validado.
- `scheduler-dr-test.log`, com múltiplas linhas que incluem `DR_TEST_SCHEDULER_001`.

## Backup manual validado

O conteúdo de `storage/app/private` foi empacotado em `tar.gz`, preservando a estrutura relativa. O archive observou os itens abaixo:

```text
./
./.gitignore
./scheduler-dr-test.log
./DR_TEST_STORAGE_001.txt
```

O artefato foi criado no staging como `laravel-private-storage.tar.gz`. Também foi criado o checksum `laravel-private-storage.tar.gz.sha256`.

## Integridade e transferência

O artefato e o checksum foram enviados por SCP, usando a chave SSH dedicada, para `/srv/backups/teste-deploy/` na máquina externa.

A validação remota de integridade foi concluída com sucesso:

```text
laravel-private-storage.tar.gz: SUCESSO
```

## Restore manual isolado validado

1. O archive e o checksum foram baixados novamente da máquina externa para `/tmp/laravel-storage-dr-restore`.
2. O SHA-256 foi validado novamente localmente, com resultado `laravel-private-storage.tar.gz: SUCESSO`.
3. O conteúdo foi extraído em `/tmp/laravel-storage-restore-test`.
4. O storage original não foi sobrescrito.

### Validação do marcador de storage

O arquivo abaixo foi recuperado no diretório isolado e seu conteúdo foi validado corretamente:

```text
/tmp/laravel-storage-restore-test/DR_TEST_STORAGE_001.txt
```

Conteúdo recuperado:

```text
DISASTER_RECOVERY_STORAGE_TEST
Este arquivo simula um dado persistente da aplicacao Laravel.
Ele deve existir apos um futuro processo de backup e restore.
```

### Validação do log do Scheduler

O arquivo abaixo foi recuperado no diretório isolado:

```text
/tmp/laravel-storage-restore-test/scheduler-dr-test.log
```

Foram encontradas múltiplas linhas com `DR_TEST_SCHEDULER_001`.

## Resultado final

O ciclo abaixo foi validado manualmente:

```text
Laravel storage original
→ tar.gz
→ staging local
→ SHA-256
→ SCP
→ máquina externa
→ checksum remoto
→ download do backup externo
→ checksum local
→ extração isolada
→ validação DR_TEST_STORAGE_001.txt
→ validação DR_TEST_SCHEDULER_001
```

O teste comprova backup de arquivos persistentes, transferência externa, verificação de integridade e recuperação isolada dos dois marcadores. Posteriormente, o restore point `2026-09-24_173106` foi extraído no caminho definitivo em máquina limpa, recuperando `DR_TEST_STORAGE_001.txt` e `scheduler-dr-test.log`.

## Limitações e pendências

- O script `backup-laravel-storage.sh`, o orquestrador, o manifesto, lock e retenção já existem e foram validados; restore automatizado ainda não existe.
- A nomenclatura por `RUN_ID` é aplicada pela execução geral.
- Monitoramento ativo/alertas permanecem pendentes.
- A estratégia de secrets e sua criptografia continuam pendentes.
- O restore manual no caminho definitivo e em máquina limpa foi validado; permissões e ownership continuam exigindo validação por host.
- `portainer_data` também foi incluído e validado no restore limpo.

## Situação atual

Este documento preserva o fluxo manual do Laravel storage como referência histórica. Scripts, orquestrador e wrapper de Cron existem em documentos próprios; nenhum secret foi exposto nesta documentação.
