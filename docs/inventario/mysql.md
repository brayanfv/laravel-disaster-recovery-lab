# MySQL — TESTE-DEPLOY

## Instalação e serviço

- Tipo: Host
- Versão do servidor: `8.0.46-0ubuntu0.24.04.3` (Ubuntu)
- Serviço: `mysql.service` ativo e em execução
- Unidade systemd: `/usr/lib/systemd/system/mysql.service`
- Escuta local:
  - `127.0.0.1:3306` (protocolo MySQL)
  - `127.0.0.1:33060` (MySQL X Protocol)
- Datadir efetivo: `/var/lib/mysql/`
- Engine padrão: `InnoDB`
- `innodb_file_per_table`: `ON`

## Bancos existentes

| Banco | Classificação | Observação |
|---|---|---|
| `information_schema` | Interno MySQL | Metadados do servidor. |
| `mysql` | Interno MySQL | Contas, permissões e dados administrativos. |
| `performance_schema` | Interno MySQL | Métricas e instrumentação. |
| `sys` | Interno MySQL | Views auxiliares de diagnóstico. |
| `teste_deploy` | Banco da aplicação | Único banco de aplicação identificado. |

## Estrutura de `teste_deploy`

As contagens abaixo são estimativas de `information_schema.tables`, portanto podem não ser exatas para tabelas InnoDB.

| Tabela | Engine | Linhas aprox. | Tamanho aprox. | Finalidade aparente |
|---|---|---:|---:|---|
| `cache` | InnoDB | 0 | 32 KiB | Cache Laravel em banco. |
| `cache_locks` | InnoDB | 0 | 16 KiB | Locks do cache Laravel. |
| `failed_jobs` | InnoDB | 0 | 16 KiB | Falhas de filas Laravel. |
| `job_batches` | InnoDB | 0 | 16 KiB | Metadados de lotes de jobs. |
| `jobs` | InnoDB | 0 | 16 KiB | Jobs pendentes em fila. |
| `migrations` | InnoDB | 2 | 16 KiB | Histórico de migrations aplicadas. |
| `password_reset_tokens` | InnoDB | 0 | 16 KiB | Tokens de redefinição de senha. |
| `sessions` | InnoDB | 6.604 | 5.680 KiB | Sessões Laravel em banco. |
| `users` | InnoDB | 2 | 32 KiB | Contas de usuários da aplicação. |

## Estado Laravel no MySQL

| Recurso Laravel | Tabela | Estado no levantamento | Classificação |
|---|---|---|---|
| Migrations | `migrations` | Presente, 2 linhas aproximadas | Metadado persistente de aplicação |
| Usuários | `users` | Presente, 2 linhas aproximadas | Dado persistente de negócio |
| Sessões | `sessions` | Presente, 6.604 linhas aproximadas | Dado temporário operacional; perda encerra sessões ativas |
| Cache | `cache` | Presente, sem linhas estimadas | Cache/temporário reconstruível |
| Locks de cache | `cache_locks` | Presente, sem linhas estimadas | Cache/temporário reconstruível |
| Fila pendente | `jobs` | Presente, sem linhas estimadas | Dado operacional potencialmente persistente |
| Batches de fila | `job_batches` | Presente, sem linhas estimadas | Dado operacional potencialmente persistente |
| Falhas de fila | `failed_jobs` | Presente, sem linhas estimadas | Dado operacional para diagnóstico/recuperação |

Nenhum conteúdo de sessão, payload de job, token ou registro de usuário foi lido ou registrado.

## Contas e privilégios

| Conta | Host | Classificação/escopo identificado |
|---|---|---|
| `root` | `localhost` | Conta administrativa local do MySQL. |
| `debian-sys-maint` | `localhost` | Conta de manutenção do sistema. |
| `laravel` | `localhost` | Conta da aplicação identificada. |
| `mysql.infoschema` | `localhost` | Conta interna MySQL. |
| `mysql.session` | `localhost` | Conta interna MySQL. |
| `mysql.sys` | `localhost` | Conta interna MySQL. |

A conta `laravel` possui privilégio global `USAGE` e privilégios de schema sobre `teste_deploy` que incluem operações de leitura, escrita e definição de estrutura, como `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `ALTER`, `DROP`, `INDEX`, `TRIGGER` e `LOCK TABLES`. Nenhuma senha, hash, plugin de autenticação ou credencial foi inspecionado.

## Configuração e arquivos

| Arquivo ou diretório | Classificação preliminar | Observação |
|---|---|---|
| `/etc/mysql/mysql.cnf` | Configuração padrão do pacote | Pertence a `mysql-server-8.0`. |
| `/etc/mysql/mysql.conf.d/mysqld.cnf` | Configuração base do servidor | Pertence ao pacote; define os binds locais identificados. Alterações locais não foram comparadas ao padrão distribuído. |
| `/etc/mysql/mysql.conf.d/mysql.cnf` | Configuração padrão do pacote | Pertence a `mysql-server-8.0`. |
| `/etc/mysql/conf.d/mysql.cnf` | Configuração padrão do pacote | Pertence a `mysql-common`. |
| `/etc/mysql/conf.d/mysqldump.cnf` | Configuração padrão do pacote | Pertence a `mysql-common`; não foi executado `mysqldump`. |
| `/etc/mysql/my.cnf.fallback` | Configuração padrão do pacote | Pertence a `mysql-common`. |
| `/etc/mysql/debian-start` | Script padrão do pacote | Pertence a `mysql-server-8.0`; não foi executado. |
| `/etc/mysql/debian.cnf` | Configuração local sensível | Não pertence ao pacote; não foi aberto por poder conter credenciais. |
| `/var/lib/mysql/` | Dados persistentes do servidor | Datadir efetivo; acesso direto não foi necessário nem obtido. |
| `/var/log/mysql/` | Logs operacionais | Localização identificada no inventário do host; conteúdo não inspecionado. |

Configurações efetivas relevantes: `bind-address = 127.0.0.1`, `mysqlx-bind-address = 127.0.0.1`, porta `3306`, MySQL X em `33060`, datadir `/var/lib/mysql/` e engine padrão InnoDB.

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| MySQL Server | Software reconstruível | Reinstalar versão compatível e validar a configuração. |
| Arquivos de `/etc/mysql` pertencentes a pacotes | Configuração do sistema | Reinstaláveis; comparar customizações antes de reproduzir. |
| `/etc/mysql/debian.cnf` | Configuração com secret | Tratar como dado sensível; não expor ou versionar credenciais. |
| Bancos internos | Dados e metadados de sistema | Mantidos pelo MySQL; não são dados de negócio da aplicação. |
| Banco `teste_deploy` | Dado persistente | Banco principal da aplicação. |
| `users` | Dado persistente de negócio | Preservação necessária para continuidade funcional. |
| `migrations` | Metadado persistente | Necessário para consistência do histórico de schema. |
| `sessions`, `cache`, `cache_locks` | Temporário operacional/cache | Sessões afetam usuários conectados; cache e locks são reconstruíveis. |
| `jobs`, `job_batches`, `failed_jobs` | Dados operacionais de fila | Vazios no levantamento; validar antes de qualquer recuperação futura. |
| Logs MySQL | Logs operacionais | Avaliar retenção; não representam dado de negócio. |

## Pendências

- Obter medição autorizada do uso real de `/var/lib/mysql` e do schema `teste_deploy`, pois o datadir não é legível pelo usuário atual.
- Confirmar se há customizações locais nos arquivos de configuração pertencentes a pacotes por comparação controlada com suas versões distribuídas.
- Revalidar tabelas de filas antes de qualquer procedimento futuro, caso jobs passem a ser utilizados.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento do MySQL no ambiente `TESTE-DEPLOY`.

Nenhum banco, tabela, usuário, privilégio, registro, serviço, migration, seeder ou configuração foi alterado durante este levantamento.
