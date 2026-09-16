# Laravel storage — TESTE-DEPLOY

## Estado do storage

- Tamanho total de `storage`: aproximadamente 672 KB.
- `storage/app`: aproximadamente 48 KB.
- `storage/framework`: aproximadamente 444 KB.
- `storage/logs`: aproximadamente 176 KB.
- `public/storage`: inexistente; o link simbólico de `storage:link` não foi criado.

## Dados da aplicação

| Localização | Conteúdo identificado | Classificação |
|---|---|---|
| `storage/app/private` | Somente `.gitignore` | Área potencial para dado persistente; sem arquivos de aplicação no levantamento. |
| `storage/app/public` | Somente `.gitignore` | Área potencial para uploads públicos; sem arquivos de aplicação no levantamento. |
| `storage/app` | Somente arquivos `.gitignore` nas áreas inspecionadas | Não há upload, documento ou arquivo público persistente identificado. |
| `public/storage` | Ausente | Nenhum conteúdo público é servido via symlink neste momento. |

## Dados temporários e logs

| Localização | Tamanho aprox. | Conteúdo identificado | Classificação |
|---|---:|---|---|
| `storage/framework/cache` | 32 KB | Apenas arquivos de controle/`.gitignore` | Cache temporário/reconstruível |
| `storage/framework/sessions` | 16 KB | Apenas arquivo de controle/`.gitignore` | Não usado para sessões efetivas; o driver atual é `database` |
| `storage/framework/views` | 364 KB | Templates Blade compilados | Cache temporário/reconstruível |
| `storage/framework/testing` | Sem dados operacionais identificados | Arquivo de controle | Temporário de testes |
| `storage/logs/laravel.log` | ~146 KB de conteúdo; diretório com 176 KB | Log local da aplicação; conteúdo não inspecionado | Log operacional |

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| `storage/app/private` | Dado persistente potencial | Preservar quando houver arquivos de aplicação; está vazio no levantamento. |
| `storage/app/public` | Dado persistente potencial | Preservar quando houver uploads públicos; está vazio no levantamento. |
| `storage/framework/cache` | Cache/temporário | Reconstruível. |
| `storage/framework/views` | Cache/temporário | Reconstruível. |
| `storage/framework/sessions` | Cache/temporário | Não contém sessões efetivas com o driver `database`. |
| `storage/logs` | Log | Avaliar retenção; não é dado essencial ao restore básico. |
| `public/storage` | Link simbólico reconstruível | Ausente; não recriar sem decisão explícita. |

## Pendências

- Reinspecionar `storage/app/private` e `storage/app/public` quando a aplicação passar a receber arquivos de usuários.
- Confirmar, em levantamento do MySQL, as sessões, cache e possíveis filas que não ficam em filesystem.
- Definir posteriormente qualquer estratégia de backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento do storage Laravel no ambiente `TESTE-DEPLOY`.

Nenhum arquivo de storage, log, cache ou link simbólico foi criado, alterado ou removido durante este levantamento.
