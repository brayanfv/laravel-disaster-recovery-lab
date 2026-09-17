# MongoDB — TESTE-DEPLOY

## Finalidade no laboratório

O MongoDB foi adicionado como componente persistente do laboratório de disaster recovery. Seu objetivo é permitir validar, futuramente, cenários que envolvam banco documental, volume Docker e recuperação de dados persistentes.

## Execução e versão

| Item | Estado confirmado |
|---|---|
| Tipo | Container Docker gerenciado por Docker Compose |
| Arquivos de infraestrutura | `infra/compose.yml`, `infra/.env` e `infra/.env.example` |
| Imagem | `mongo:8.0.32-noble` |
| Versão do MongoDB | 8.0.32 |
| Container | `teste-deploy-mongodb` |
| Política de restart | `unless-stopped`; comportamento pós-restart validado no teste de persistência |
| Porta interna | `27017/tcp` |
| Porta publicada no host | Não há publicação de `27017` para o host |

O serviço é acessível somente pela rede Docker associada à stack Compose. O nome e as características detalhadas dessa network não foram registrados neste documento e permanecem pendentes de inventário específico, se necessários.

## Configuração e secrets

| Item | Classificação | Versionamento |
|---|---|---|
| `infra/compose.yml` | Configuração de infraestrutura versionável; não contém passwords diretamente | Pode ser versionado |
| `infra/.env.example` | Modelo com placeholders seguros | Pode ser versionado |
| `infra/.env` | Credenciais locais fictícias do laboratório e configuração de inicialização | Não versionar; é ignorado pelo Git |

Nenhum valor de usuário, senha ou outro secret de `infra/.env` é reproduzido neste documento.

## Persistência

| Item | Estado confirmado |
|---|---|
| Volume nomeado | `mongodb_data` |
| Destino no container | `/data/db` |
| Natureza dos dados | Persistente; não fica no filesystem efêmero do container |
| Docker data-root | `/srv/teste-deploy-data/docker` |
| Localização física do volume | Sob o data-root Docker na partição `/srv/teste-deploy-data` |

O volume `mongodb_data` reside na partição dedicada ao Docker. Essa partição é local e fica no mesmo disco físico do host; ela amplia capacidade, mas não constitui armazenamento externo de backup.

## Teste de persistência

Foi realizado o teste deliberado `DR_TEST_MONGO_001` no banco `teste_deploy_lab`, coleção `recovery_tests`.

| Etapa | Resultado |
|---|---|
| Inserção do registro de validação | Concluída com sucesso |
| Consulta antes do restart | Registro encontrado |
| Parada do container com Docker Compose | Concluída |
| Nova inicialização do container com Docker Compose | Concluída |
| Consulta após o restart | Registro permaneceu existente |

O teste valida a persistência de `mongodb_data` após restart do container. Ele não valida backup, restauração de volume, recuperação após perda do host ou restore em máquina limpa.

## Kernel e compatibilidade

- MongoDB 8.0.32 apresentou incompatibilidade com o kernel `7.0.0-30` usado inicialmente.
- O host foi inicializado com `6.8.0-139-generic`, linha GA 6.8, e o MongoDB iniciou normalmente.
- Os pacotes HWE/kernel 7.0 foram removidos posteriormente.

O kernel GA 6.8 é uma dependência operacional relevante para o estado validado do laboratório. Não foi feita uma matriz completa de compatibilidade de versões de MongoDB e kernel.

## Warnings observados no startup

Os avisos abaixo foram observados sem impedir o funcionamento do MongoDB:

- recomendação de XFS para WiredTiger;
- soft limit de descritores de arquivo abaixo do recomendado;
- recomendações relacionadas a Transparent Huge Pages;
- recomendação de `swappiness` igual a 0 ou 1.

Esses itens representam tuning pendente para um cenário de produção. Não foram alterados filesystem, `sysctl`, limites de processo ou parâmetros do MongoDB nesta etapa.

## Classificação para disaster recovery

| Item | Classificação | Tratamento futuro |
|---|---|---|
| Container `teste-deploy-mongodb` | Serviço reconstruível | Recriar pelo Compose e imagem fixa compatível |
| Imagem `mongo:8.0.32-noble` | Dependência reconstruível | Baixar novamente pela tag fixa; avaliar digest futuramente |
| `infra/compose.yml` e `infra/.env.example` | Configuração versionável | Manter em Git |
| `infra/.env` | Secret/configuração local | Manter fora do Git e tratar de forma protegida |
| Volume `mongodb_data` | Dado persistente | Preservar e incluir futuramente no escopo de backup e recuperação |
| Registro `DR_TEST_MONGO_001` | Dado de validação persistente | Útil para verificações futuras de recuperação |

## Pendências

- Definir e implementar estratégia de backup/restore do MongoDB; ainda não existe script, dump ou procedimento validado.
- Validar restore do MongoDB em máquina limpa ou ambiente equivalente.
- Decidir o nível de backup necessário para o volume `mongodb_data` e para dados lógicos do banco.
- Avaliar tuning de produção para filesystem, limites de descritores, Transparent Huge Pages e `swappiness`.
- Registrar detalhes da network Compose somente se forem necessários para a futura reconstrução.
- Decidir se a imagem deverá ser fixada também por digest.

## Situação atual

Este documento representa o MongoDB instalado e validado no laboratório `TESTE-DEPLOY`. A persistência após restart do container foi validada; backup, restore e recuperação em máquina limpa continuam pendentes.
