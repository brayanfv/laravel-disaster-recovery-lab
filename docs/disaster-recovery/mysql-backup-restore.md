# Backup e restore manual do MySQL — TESTE-DEPLOY

## Objetivo

Registrar o primeiro fluxo real de backup e restore validado no laboratório para o banco da aplicação `teste_deploy`.

O fluxo validou a cadeia completa: banco original, dump lógico, staging local, SHA-256, transferência por SCP ao destino externo, validação remota, download de volta, nova validação local, restore em banco isolado e validações de estrutura e dados.

## Pré-requisitos e princípio de menor privilégio

- Banco de origem: `teste_deploy`.
- Usuário usado para dump e restore: `laravel`.
- Staging local: `/srv/teste-deploy-data/backup-staging/mysql`.
- Destino externo: `teste@172.23.1.115:/srv/backups/teste-deploy/`.
- A transferência usa a chave SSH dedicada já documentada na arquitetura de backup.

O usuário `laravel` não possui privilégio global para criar bancos. Uma tentativa de criar `teste_deploy_restore_test` retornou `Access denied`.

Esse comportamento foi mantido como aplicação do princípio de menor privilégio: não foi concedido privilégio global adicional à conta da aplicação. Para o teste de restore, o banco isolado foi criado por usuário administrativo via `sudo mysql`, e a conta `laravel` recebeu acesso somente ao banco de teste.

## Backup manual validado

O primeiro comando de dump usou `--single-transaction`, `--routines`, `--triggers` e `--events`, mas falhou durante a consulta de tablespaces por falta do privilégio `PROCESS`.

O método validado incluiu `--no-tablespaces`, evitando a leitura de tablespaces que exige esse privilégio global:

```bash
mysqldump \
  -u laravel \
  -p \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --no-tablespaces \
  teste_deploy > teste_deploy.sql
```

Nenhuma senha é registrada neste documento. A opção `-p` solicita a credencial de forma interativa.

Resultados validados:

- Dump gerado com aproximadamente 2,1 MB.
- Cabeçalho do arquivo confirmou MySQL dump 8.0.46, banco `teste_deploy` e servidor `8.0.46-0ubuntu0.24.04.3`.

## Integridade e transferência

O checksum foi gerado no staging com caminho relativo:

```bash
sha256sum teste_deploy.sql > teste_deploy.sql.sha256
```

O dump e seu checksum foram transferidos por SCP, usando a chave dedicada, para `/srv/backups/teste-deploy/` na máquina externa.

A validação remota foi concluída com sucesso:

```text
teste_deploy.sql: SUCESSO
```

## Restore manual validado

1. O dump e o checksum foram baixados novamente da máquina externa para `/tmp/mysql-dr-restore`.
2. O SHA-256 foi validado novamente no ambiente local, com resultado `teste_deploy.sql: SUCESSO`.
3. O restore foi executado no banco isolado `teste_deploy_restore_test`, criado administrativamente.
4. O dump recuperado da máquina externa foi restaurado com sucesso pela conta `laravel`, limitada a esse banco de teste.

### Validação estrutural

As tabelas abaixo foram encontradas após o restore:

- `cache`
- `cache_locks`
- `failed_jobs`
- `job_batches`
- `jobs`
- `migrations`
- `password_reset_tokens`
- `sessions`
- `users`

### Validação de dados

| Verificação | Resultado |
|---|---:|
| `users_count` | 2 |
| `sessions_count` | 7108 |

## Resultado final

O fluxo abaixo foi validado manualmente:

```text
MySQL original
→ mysqldump
→ staging local
→ SHA-256
→ transferência SSH/SCP
→ máquina externa
→ checksum remoto
→ download do backup externo
→ checksum local
→ banco isolado
→ restore
→ validação de estrutura
→ validação de dados
```

O teste comprova o backup lógico e o restore manual isolado de `teste_deploy`, incluindo a integridade do artefato antes e depois da transferência externa. Não comprova restore da aplicação inteira nem recuperação em máquina limpa.

## Limitações e pendências

- Não há script de backup ou restore.
- A nomenclatura do artefato ainda não incorpora data/hora ou versão.
- Não há retenção automatizada, monitoramento ou alertas.
- A estratégia de secrets e sua criptografia continuam pendentes.
- O restore ainda não foi validado em máquina totalmente limpa.
- Backup e restore dos demais componentes persistentes, como MongoDB, Redis, Laravel storage e `portainer_data`, continuam pendentes.

## Situação atual

Este documento registra somente o fluxo manual de MySQL já validado. Nenhum agendamento Cron de backup, script, alteração de privilégio global, senha ou secret foi criado ou exposto nesta documentação.
