# Laravel Scheduler — TESTE-DEPLOY

## Estado atual

- `php artisan schedule:list` não encontrou tarefas agendadas.
- Não há referências a `Schedule::` nem a `schedule:run` nos diretórios `routes`, `app`, `bootstrap` e `config` inspecionados.
- Não foi executado `schedule:run`.

## Tarefas identificadas

Nenhuma tarefa Laravel agendada foi identificada no momento do levantamento.

| Item | Estado | Observação |
|---|---|---|
| Tarefas Laravel agendadas | Ausentes | `schedule:list` retornou que nenhuma tarefa foi definida. |
| Disparo por Cron | Não identificado | Não há job `schedule:run` nos agendamentos Cron visíveis. |
| Worker de filas | Não identificado | Não há processo, unidade systemd ou configuração Supervisor relacionada. |

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| Definições do Scheduler | Código/configuração | Ausentes; reproduzir por versionamento se forem adicionadas. |
| Disparo `schedule:run` por Cron | Tarefa reproduzível/documentável | Ausente; criar somente sob decisão futura explícita. |
| Jobs de fila | Dado operacional potencial | Não há código ou worker identificado; fila efetiva usa banco de dados. |

## Pendências

- Revalidar este documento quando forem adicionadas tarefas em `routes/console.php` ou outras definições de Scheduler.
- Revalidar Cron se um disparo de `schedule:run` for configurado no futuro.
- Inventariar as tabelas de fila no MySQL caso o uso de jobs seja introduzido.
- Definir posteriormente qualquer estratégia de backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento do Laravel Scheduler no ambiente `TESTE-DEPLOY`.

Nenhuma tarefa agendada, worker ou fila foi executado, iniciado, alterado ou removido durante este levantamento.
