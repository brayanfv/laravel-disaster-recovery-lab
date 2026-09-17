# Laravel Scheduler — TESTE-DEPLOY

## Estado atual

- Existe uma tarefa Laravel Scheduler real, definida em `routes/console.php`.
- A tarefa é executada a cada minuto.
- `php artisan schedule:list` identificou a descrição `Append the scheduler disaster recovery marker`.
- O crontab do usuário `lucas-cooperja` dispara `php artisan schedule:run` a cada minuto; a tarefa é executada automaticamente pelo sistema.

## Tarefa identificada

| Item | Estado | Observação |
|---|---|---|
| Implementação | Presente | `routes/console.php` usa `Schedule::call(...)`. |
| Frequência | Validada | A cada minuto (`* * * * *`). |
| Finalidade | Validada | Acrescentar um marcador de disaster recovery ao storage privado da aplicação. |
| Arquivo gerado | Presente | `storage/app/private/scheduler-dr-test.log`. |
| Marcador | Validado | Cada execução registra timestamp e `DR_TEST_SCHEDULER_001`. |
| Dependências diretas | Não utilizadas | A tarefa usa `Storage::disk('local')->append(...)` e não depende diretamente de MySQL, Redis ou MongoDB. |
| Disparo por Cron | Validado | O crontab de `lucas-cooperja` executa `schedule:run` a cada minuto. |

## Validação realizada

- `php artisan schedule:list` exibiu a tarefa `Append the scheduler disaster recovery marker` com frequência a cada minuto.
- A execução manual com `CACHE_STORE=file php artisan schedule:run` foi concluída e acrescentou o marcador ao log.
- `CACHE_STORE=file` foi usado somente no processo de validação; o `.env` não foi alterado.
- Não foi aplicada configuração global ao Scheduler: não há `Schedule::$pausable = false` nem `Schedule::useCache('file')`.
- A integração automática foi validada pelo Cron do usuário: a contagem de `DR_TEST_SCHEDULER_001` cresceu de 3 para 7 ocorrências após alguns minutos.
- Timestamps observados automaticamente: `2026-09-17 19:56:01`, `2026-09-17 19:57:01`, `2026-09-17 19:58:01` e `2026-09-17 19:59:01`, todos com o marcador `DR_TEST_SCHEDULER_001`.

### Teste focal

O teste `tests/Feature/SchedulerDrTest.php` valida a tarefa de forma isolada.

- Resultado validado: 1 teste aprovado, com 2 assertions.
- O teste define `cache.default` como `file` apenas no processo de teste.
- O teste confirma a criação do arquivo e o conteúdo do marcador no disco `local` simulado.

## Persistência e Git

O arquivo `storage/app/private/scheduler-dr-test.log` existe, contém linhas com `DR_TEST_SCHEDULER_001` e é ignorado pela regra `*` em `storage/app/private/.gitignore`.

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| `routes/console.php` | Código/configuração versionável | Reconstruível por Git quando versionado. |
| `tests/Feature/SchedulerDrTest.php` | Teste versionável | Reconstruível por Git quando versionado. |
| `storage/app/private/scheduler-dr-test.log` | Dado operacional/persistente | Preservar e considerar na futura estratégia de backup conforme o papel do Scheduler no cenário. |
| Cache de filesystem usado na validação | Temporário | Usado somente pelo comando ou teste; não altera a configuração permanente da aplicação. |
| Disparo `schedule:run` por Cron | Configuração personalizada de usuário | Validado no crontab de `lucas-cooperja`; reproduzir/documentar em reconstrução futura. |

## Classificação para disaster recovery

- A definição da tarefa e seu teste são código reconstruível por versionamento, desde que incluídos no repositório.
- O log gerado no storage privado é dado operacional persistente do laboratório e não é recuperável por clone do Git.
- Ainda não houve backup nem restore do log ou da definição em máquina limpa.
- A automação pelo Cron do host foi validada, mas a restauração em máquina limpa e a estratégia de backup continuam pendentes.

## Pendências

- Validar backup e restore do log do Scheduler em máquina limpa ou ambiente equivalente.
- Definir posteriormente qualquer estratégia de backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento registra a tarefa Scheduler e sua integração automática com o Cron do usuário `lucas-cooperja`, ambas validadas no ambiente `TESTE-DEPLOY`. Isso não implementa backup, restore ou validação de recuperação em máquina limpa.
