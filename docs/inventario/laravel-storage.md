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
| `storage/app/private` | `.gitignore`, `DR_TEST_STORAGE_001.txt` (155 bytes) e `scheduler-dr-test.log` | Dados persistentes privados da aplicação; não versionados. |
| `storage/app/public` | Somente `.gitignore` | Área potencial para uploads públicos; sem arquivos de aplicação no levantamento. |
| `storage/app` | Marcador privado de disaster recovery; não há upload ou arquivo público persistente identificado | Possui dado persistente privado representativo; fluxo público ainda não validado. |
| `public/storage` | Ausente | Nenhum conteúdo público é servido via symlink neste momento. |

### Marcador privado de disaster recovery

O arquivo `storage/app/private/DR_TEST_STORAGE_001.txt` foi criado e validado como dado persistente fictício da aplicação.

- Finalidade: marcador para teste futuro de backup e restore do storage Laravel.
- Conteúdo: marcador de teste de disaster recovery confirmado; não contém dado sensível.
- Git: não aparece em `git status` porque `storage/app/private/.gitignore` possui a regra `*`.

O conteúdo de `storage/app/private` deve ser tratado como dado persistente da aplicação. Ele não pode ser reconstruído somente por clone do repositório Git.

### Log de validação do Scheduler

O arquivo `storage/app/private/scheduler-dr-test.log` é gerado pela tarefa Laravel Scheduler validada em `routes/console.php`.

- Finalidade: registrar execuções do marcador `DR_TEST_SCHEDULER_001` com timestamp.
- Classificação: dado operacional/persistente do laboratório.
- Git: é ignorado pela mesma regra `*` em `storage/app/private/.gitignore`.
- Situação: a criação e a escrita foram validadas; backup, restore e validação em máquina limpa ainda não foram realizados.

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
| `storage/app/private` | Dado persistente | Preservar; contém o marcador `DR_TEST_STORAGE_001.txt` e o log `scheduler-dr-test.log`, ambos ignorados pelo Git. |
| `storage/app/public` | Dado persistente potencial | Preservar quando houver uploads públicos; está vazio no levantamento. |
| `storage/framework/cache` | Cache/temporário | Reconstruível. |
| `storage/framework/views` | Cache/temporário | Reconstruível. |
| `storage/framework/sessions` | Cache/temporário | Não contém sessões efetivas com o driver `database`. |
| `storage/logs` | Log | Avaliar retenção; não é dado essencial ao restore básico. |
| `public/storage` | Link simbólico reconstruível | Ausente; não recriar sem decisão explícita. |

## Pendências

- Realizar futuramente backup e restore do marcador `DR_TEST_STORAGE_001.txt`; isso ainda não foi testado.
- Realizar futuramente backup e restore do log `scheduler-dr-test.log`; isso ainda não foi testado.
- Validar futuramente a recuperação do storage privado em máquina limpa ou ambiente equivalente.
- Reinspecionar `storage/app/public` quando a aplicação passar a receber arquivos de usuários.
- Confirmar, em levantamento do MySQL, as sessões, cache e possíveis filas que não ficam em filesystem.
- Definir posteriormente qualquer estratégia de backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento preserva o inventário inicial e registra o marcador privado de disaster recovery criado posteriormente. O arquivo existe e é persistente, mas seu backup, restore e validação em máquina limpa continuam pendentes.
