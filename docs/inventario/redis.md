# Redis — TESTE-DEPLOY

## Finalidade no laboratório

O Redis foi adicionado como armazenamento operacional persistente de curta duração para o laboratório de disaster recovery. Ele representa cenários possíveis de filas, sessões e estados temporários importantes.

O Laravel atual não utiliza Redis. Cache, sessão e fila continuam configurados com driver `database`; não há integração Redis/Laravel validada neste ambiente.

## Execução e rede

| Item | Estado confirmado |
|---|---|
| Tipo | Container Docker gerenciado por Docker Compose |
| Arquivo de infraestrutura | `infra/compose.yml` |
| Imagem | `redis:7.4.11-alpine` |
| Container | `teste-deploy-redis` |
| Política de restart | `unless-stopped` |
| Porta interna | `6379/tcp` |
| Porta publicada no host | Não há publicação de `6379` para o host |
| Rede | Mesma rede Docker Compose da stack MongoDB |

O Redis não possui senha configurada nesta etapa. O acesso está limitado à rede Docker interna do laboratório; requisitos de autenticação e segurança permanecem pendentes de decisão separada.

## Persistência

| Item | Estado confirmado |
|---|---|
| Persistência Redis | AOF habilitado por `redis-server --appendonly yes` |
| Volume nomeado | `redis_data` |
| Destino no container | `/data` |
| Docker data-root | `/srv/teste-deploy-data/docker` |
| Mountpoint físico validado | `/srv/teste-deploy-data/docker/volumes/redis_data/_data` |

Os dados não dependem somente do filesystem efêmero do container: a persistência AOF é gravada no volume `redis_data`, localizado na partição dedicada ao Docker. Essa partição está no mesmo disco físico do host e não representa destino externo de backup.

## Teste de persistência

Foi executado o teste deliberado `DR_TEST_REDIS_001`.

| Etapa | Resultado |
|---|---|
| Criação da chave de validação com `SET` | Concluída com sucesso |
| Consulta inicial com `GET` | Chave encontrada |
| Parada do container com Docker Compose | Concluída |
| Nova inicialização do container com Docker Compose | Concluída |
| Consulta após restart | Valor permaneceu existente |

O teste valida a persistência de `redis_data` após restart do container. Ele não valida backup, restauração do volume, recuperação após perda do host ou restore em máquina limpa.

## Cache descartável e dado operacional persistente

Redis pode atuar como cache descartável, situação em que seus dados normalmente podem ser recriados e talvez não demandem backup. Neste laboratório, AOF e o volume persistente foram habilitados para representar também estados operacionais de curta duração que podem ser importantes.

A necessidade real de backup dependerá do papel que Redis desempenhará em produção:

| Papel futuro | Natureza provável | Decisão futura |
|---|---|---|
| Cache puramente descartável | Temporário/reconstruível | Pode não precisar de backup |
| Filas, sessões ou estado operacional relevante | Dado operacional persistente | Avaliar inclusão em backup e recuperação |

## Classificação para disaster recovery

| Item | Classificação | Tratamento futuro |
|---|---|---|
| Container `teste-deploy-redis` | Serviço reconstruível | Recriar pelo Compose e imagem fixa compatível |
| Imagem `redis:7.4.11-alpine` | Dependência reconstruível | Baixar novamente pela tag fixa; avaliar digest futuramente |
| `infra/compose.yml` | Configuração versionável | Manter em Git |
| Volume `redis_data` | Dado operacional persistente | Preservar; decidir backup conforme papel real em produção |
| Registro `DR_TEST_REDIS_001` | Dado de validação persistente | Útil para verificações futuras de recuperação |

## Pendências

- Definir se Redis representará cache descartável, filas, sessões ou outro estado relevante no cenário de produção.
- Definir estratégia de backup/restore somente se o papel futuro justificar a preservação dos dados Redis.
- Validar restore do volume e recuperação do Redis em máquina limpa ou ambiente equivalente.
- Avaliar autenticação, controle de acesso e demais requisitos de segurança para uso além da rede Docker interna do laboratório.
- Decidir se a imagem deverá ser fixada também por digest.

## Situação atual

Este documento registra o Redis instalado e validado no laboratório `TESTE-DEPLOY`. A persistência AOF após restart do container foi validada; integração Laravel, backup, restore e recuperação em máquina limpa continuam pendentes.
