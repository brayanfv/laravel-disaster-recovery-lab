# Backup e restore manual do MongoDB — TESTE-DEPLOY

## Objetivo

Registrar o fluxo manual de backup e restore validado para o MongoDB do laboratório.

O fluxo validou: banco original, `mongodump` em archive dentro do container, staging local, SHA-256, transferência por SCP ao destino externo, validações de integridade, download do artefato, `mongorestore` em banco isolado com remapeamento de namespaces e recuperação do marcador `DR_TEST_MONGO_001`.

## Pré-requisitos

| Item | Estado confirmado |
|---|---|
| Container | `teste-deploy-mongodb` |
| Versão MongoDB | 8.0.32 |
| Banco de origem | `teste_deploy_lab` |
| Coleção de validação | `recovery_tests` |
| Marcador | `DR_TEST_MONGO_001` |
| Staging local | `/srv/teste-deploy-data/backup-staging/mongodb` |
| Destino externo | `teste@172.23.1.115:/srv/backups/teste-deploy/` |

O dump e o restore foram executados dentro do container. A senha foi obtida por variável temporária, sem ser gravada no histórico do shell ou neste documento.

## Backup manual validado

O uso de `--password` sem argumento falhou porque o `mongodump` exige um valor explícito. Para evitar a senha no histórico, foi usado `read -s MONGO_BACKUP_PASSWORD` e a variável foi disponibilizada temporariamente ao container com `docker exec -e`.

O comando conceitual validado utilizou:

```text
mongodump
  --username <usuário administrativo do laboratório>
  --password "$MONGO_BACKUP_PASSWORD"
  --authenticationDatabase admin
  --db teste_deploy_lab
  --archive=/tmp/teste_deploy_lab.archive
```

Nenhum valor de senha ou conteúdo de credencial é registrado. A exportação da coleção `recovery_tests` foi concluída com 1 documento.

O archive foi criado no container em `/tmp/teste_deploy_lab.archive` e copiado para o host em:

```text
/srv/teste-deploy-data/backup-staging/mongodb/teste_deploy_lab.archive
```

## Integridade e transferência

O checksum foi gerado no staging com caminho relativo:

```bash
sha256sum teste_deploy_lab.archive > teste_deploy_lab.archive.sha256
```

O archive e seu checksum foram enviados por SCP, usando a chave SSH dedicada, para `/srv/backups/teste-deploy/` na máquina externa.

A validação remota de integridade foi concluída com sucesso:

```text
teste_deploy_lab.archive: SUCESSO
```

## Restore manual isolado validado

1. O archive e o checksum foram baixados novamente da máquina externa para `/tmp/mongodb-dr-restore`.
2. O SHA-256 foi validado novamente localmente.
3. O archive foi copiado de volta para dentro do container MongoDB.
4. A senha de restore foi tratada por variável temporária, sem inclusão no histórico do shell.
5. O restore foi executado no banco isolado `teste_deploy_lab_restore_test` com remapeamento de namespaces:

```text
--nsFrom="teste_deploy_lab.*"
--nsTo="teste_deploy_lab_restore_test.*"
```

6. O banco original `teste_deploy_lab` não foi sobrescrito.

### Validação

No banco `teste_deploy_lab_restore_test`, a consulta por `identificador: "DR_TEST_MONGO_001"` na coleção `recovery_tests` recuperou o documento com sucesso.

| Verificação | Resultado |
|---|---:|
| Marcador `DR_TEST_MONGO_001` | Recuperado |
| `db.recovery_tests.countDocuments()` | 1 |

## Resultado final

O ciclo abaixo foi validado manualmente:

```text
MongoDB original
→ mongodump
→ archive
→ staging local
→ SHA-256
→ SCP com chave dedicada
→ máquina externa
→ checksum remoto
→ download do backup externo
→ checksum local
→ mongorestore isolado
→ validação DR_TEST_MONGO_001
```

O teste comprova backup lógico, transferência externa, verificação de integridade e restore isolado do marcador MongoDB. Ele não valida recovery do host, restore da aplicação completa, backup bruto de volume ou restore em máquina limpa.

## Limitações e pendências

- Não há script de backup ou restore.
- A nomenclatura do archive ainda não incorpora data/hora ou versão.
- Não há retenção automatizada, monitoramento ou alertas.
- A estratégia de secrets e sua criptografia continuam pendentes.
- O restore ainda não foi validado em máquina totalmente limpa.
- Backup e restore de Redis, Laravel storage e `portainer_data` continuam pendentes.

## Situação atual

Este documento registra somente o fluxo manual MongoDB já validado. Nenhum agendamento Cron de backup, script, alteração de infraestrutura ou senha foi criado ou exposto nesta documentação.
