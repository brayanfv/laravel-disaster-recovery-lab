# Backup e restore manual do Redis — TESTE-DEPLOY

## Objetivo

Registrar o fluxo manual de backup e restore validado para o Redis persistente do laboratório.

No laboratório, Redis foi tratado como estado persistente. Em produção, a necessidade de backup depende do papel real do Redis: um cache descartável pode não exigir backup, enquanto filas, sessões ou outro estado operacional relevante podem exigir preservação.

## Pré-requisitos e configuração persistente

| Item | Estado confirmado |
|---|---|
| Container original | `teste-deploy-redis` |
| Imagem | `redis:7.4.11-alpine` |
| Persistência | AOF habilitado |
| Diretório Redis | `/data` |
| Diretório AOF | `appendonlydir` |
| Volume de origem | `redis_data` |
| Marcador | `DR_TEST_REDIS_001 = disaster-recovery-test` |
| Staging local | `/srv/teste-deploy-data/backup-staging/redis` |
| Destino externo | `teste@172.23.1.115:/srv/backups/teste-deploy/` |

Layout persistente observado em `/data`:

```text
/data
├── appendonlydir/
│   ├── appendonly.aof.1.base.rdb
│   ├── appendonly.aof.1.incr.aof
│   └── appendonly.aof.manifest
└── dump.rdb
```

## Backup manual validado

1. A persistência foi forçada no Redis original com `redis-cli SAVE`, retornando `OK`.
2. O container Redis foi parado de forma controlada via Docker Compose antes da cópia do volume, para empacotar um estado persistente não alterado durante o backup.
3. O conteúdo de `/srv/teste-deploy-data/docker/volumes/redis_data/_data` foi empacotado em um arquivo `tar.gz` no staging local:

   ```text
   /srv/teste-deploy-data/backup-staging/redis/redis_data.tar.gz
   ```

4. O Redis original foi iniciado novamente, e o marcador `DR_TEST_REDIS_001` permaneceu disponível.

## Integridade e transferência

O checksum foi criado no staging com caminho relativo:

```bash
sha256sum redis_data.tar.gz > redis_data.tar.gz.sha256
```

O artefato e seu checksum foram enviados por SCP, usando a chave SSH dedicada, para `/srv/backups/teste-deploy/` na máquina externa.

A validação remota de integridade foi concluída com sucesso:

```text
redis_data.tar.gz: SUCESSO
```

## Restore manual isolado validado

1. O artefato e seu checksum foram baixados novamente da máquina externa para `/tmp/redis-dr-restore`.
2. O SHA-256 foi validado novamente localmente, com resultado `redis_data.tar.gz: SUCESSO`.
3. Foi criado o volume isolado `redis_restore_test_data`, com mountpoint observado em:

   ```text
   /srv/teste-deploy-data/docker/volumes/redis_restore_test_data/_data
   ```

4. O conteúdo do backup foi extraído nesse volume isolado.
5. Foi criado o container isolado `teste-deploy-redis-restore`, usando a imagem `redis:7.4.11-alpine` e `redis-server --appendonly yes`.
6. O container de restore iniciou corretamente.

### Validação

No container isolado, a consulta `redis-cli GET DR_TEST_REDIS_001` retornou:

```text
disaster-recovery-test
```

O volume e o container originais não foram substituídos pelo teste de restore.

## Resultado final

O ciclo abaixo foi validado manualmente:

```text
Redis original
→ persistência forçada
→ parada controlada
→ backup do volume
→ tar.gz
→ SHA-256
→ SCP
→ máquina externa
→ checksum remoto
→ download do backup externo
→ checksum local
→ volume novo
→ container Redis isolado
→ recuperação de DR_TEST_REDIS_001
```

O teste comprova backup consistente do volume persistente no laboratório, transferência externa, verificação de integridade e restore isolado. Ele não valida recovery do host, restore da aplicação completa, automação ou restore em máquina limpa.

## Limitações e pendências

- Não há script de backup ou restore.
- A nomenclatura do artefato ainda não incorpora data/hora ou versão.
- Não há retenção automatizada, monitoramento ou alertas.
- A estratégia de secrets e sua criptografia continuam pendentes.
- O restore ainda não foi validado em máquina totalmente limpa.
- Backup e restore de Laravel storage e `portainer_data` continuam pendentes.
- A necessidade de backup Redis em produção ainda depende do papel real do serviço.

## Situação atual

Este documento registra somente o fluxo manual Redis já validado no laboratório. Nenhum agendamento Cron de backup, script, alteração de infraestrutura ou segredo foi criado ou exposto nesta documentação.
