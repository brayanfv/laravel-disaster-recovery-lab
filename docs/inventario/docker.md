# Docker — TESTE-DEPLOY

## Instalação e estado

- Tipo: Host
- Docker Engine: 29.1.3
- Docker Compose: 2.40.3
- Serviço Docker: ativo
- Containers: 2 em execução e 3 parados
- Imagens locais: 4
- Volumes nomeados: 2
- Networks: 3 padrão identificadas no levantamento inicial; a stack MongoDB adicionou uma network Compose cujo detalhamento permanece pendente

## Armazenamento Docker e containerd

A migração do armazenamento persistente foi validada após reboot.

| Componente | Origem anterior | Localização atual validada | Estado |
|---|---|---|---|
| Docker data-root | `/var/lib/docker` | `/srv/teste-deploy-data/docker` | Ativo; driver `overlayfs` |
| Containerd root persistente | `/var/lib/containerd` | `/srv/teste-deploy-data/containerd` | Ativo |
| Containerd state temporário | `/run/containerd` | `/run/containerd` | Mantido como estado temporário |

`containerd` e `docker` iniciaram ativos após o reboot. Containers, imagens e volumes previamente existentes continuam visíveis.

As origens `/var/lib/docker` e `/var/lib/containerd` foram mantidas temporariamente para rollback. Elas não devem ser removidas até que haja uma decisão explícita e uma validação adicional do ambiente.

## Containers

| Container | Imagem | Estado no levantamento | Restart policy | Labels Compose | Mounts | Classificação preliminar |
|---|---|---|---|---|---|---|
| `portainer` | `portainer/portainer-ce:latest` | Em execução | `always` | Ausentes | Volume `portainer_data` em `/data`; bind do socket Docker | Serviço com estado persistente |
| `objective_beaver` | `hello-world:latest` | Parado, saída 0 há cerca de 2 semanas | `no` | Ausentes | Nenhum | Teste descartável |
| `priceless_rubin` | `ubuntu:latest` | Parado há cerca de 2 semanas | `no` | Ausentes | Nenhum | Aparentemente teste descartável |
| `trusting_margulis` | `hello-world:latest` | Parado, saída 0 há cerca de 2 semanas | `no` | Ausentes | Nenhum | Teste descartável |
| `teste-deploy-mongodb` | `mongo:8.0.32-noble` | Em execução; persistência validada após restart | `unless-stopped` | Associadas à stack Compose | Volume `mongodb_data` em `/data/db` | Serviço persistente do laboratório |

Os containers anteriores ao MongoDB não têm labels `com.docker.compose.project` nem `com.docker.compose.service`. O `teste-deploy-mongodb` é associado à stack definida em `infra/compose.yml`.

## Imagens relevantes

| Imagem | Tag | ID curto | Tamanho | Classificação preliminar |
|---|---|---|---:|---|
| `portainer/portainer-ce` | `latest` | `511f3f06c96f` | 201 MB | Imagem reconstruível/downloadable; tag não fixada por versão |
| `ubuntu` | `latest` | `2260313b31c8` | 160 MB | Imagem reconstruível/downloadable; usada apenas por container parado de teste |
| `hello-world` | `latest` | `5dd0d3e6e255` | 25,9 kB | Imagem reconstruível/downloadable; usada apenas por testes |
| `mongo` | `8.0.32-noble` | Não registrado neste inventário | Não registrado neste inventário | Imagem fixa do MongoDB do laboratório |

## Networks

| Network | Driver | Scope | Tipo | Uso identificado |
|---|---|---|---|---|
| `bridge` | `bridge` | `local` | Padrão Docker | Network do container `portainer` |
| `host` | `host` | `local` | Padrão Docker | Nenhum container associado identificado |
| `none` | `null` | `local` | Padrão Docker | Nenhum container associado identificado |

## Volumes e mounts

| Recurso | Tipo | Origem no host | Destino no container | Estado/classificação |
|---|---|---|---|---|
| `portainer_data` | Volume nomeado, driver `local` | `/srv/teste-deploy-data/docker/volumes/portainer_data/_data` | `/data` no `portainer` | Dado persistente preservado na migração |
| Socket Docker | Bind mount | `/var/run/docker.sock` | `/var/run/docker.sock` no `portainer` | Integração/configuração do container; leitura e escrita habilitadas |
| `mongodb_data` | Volume nomeado, driver `local` | Sob `/srv/teste-deploy-data/docker/volumes/` | `/data/db` no `teste-deploy-mongodb` | Dado persistente do MongoDB; persistência após restart validada |

O volume `portainer_data` foi criado em 28/08/2026, não possui labels nem opções declaradas e tem escopo `local`.

Após a migração e o reboot, o container `portainer` subiu automaticamente e o volume `portainer_data` foi preservado no novo mountpoint.

Os containers de teste não possuem volume nomeado, bind mount ou mount `tmpfs` identificado.

## Docker Compose

O primeiro levantamento não identificou recurso Compose em execução. O estado atual inclui a stack MongoDB definida em `infra/compose.yml`, com o container `teste-deploy-mongodb` e o volume `mongodb_data`. O Portainer continua sem labels Compose e não foi alterado.

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| Docker Engine e Compose | Software reconstruível | Reinstalar versões compatíveis e validar o daemon. |
| Imagens locais | Imagens reconstruíveis/downloadable | Baixar novamente por tag ou, preferencialmente, por versão/digest definido. |
| Container `portainer` | Container reconstruível | Recriar com os mounts, rede, porta e política de restart documentados. |
| Volume `portainer_data` | Dado persistente | Preservar e validar o conteúdo antes de qualquer ação futura. |
| Volume `mongodb_data` | Dado persistente | Preservar e incluir futuramente na estratégia de backup e recuperação. |
| Bind `/var/run/docker.sock` | Configuração de integração | Recriar somente se Portainer continuar administrando o daemon local. |
| Containers `hello-world` e `ubuntu` parados | Recursos descartáveis de teste | Não possuem estado persistente identificado. |
| Networks `bridge`, `host` e `none` | Recursos padrão reconstruíveis | Fornecidos pelo Docker. |

## Pendências

- Determinar uma versão ou digest fixo para a imagem do Portainer, pois atualmente é usada a tag `latest`.
- Inspecionar o conteúdo funcional de `portainer_data` somente se necessário para um inventário de dados posterior.
- Validar se a linha sem status/arquivos retornada por `docker compose ls --all` representa metadado residual ou projeto incompleto; ela não está associada a containers por labels.
- Decidir, somente após período adicional de validação, o destino das origens antigas em `/var/lib/docker` e `/var/lib/containerd`, mantidas para rollback.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento registra o inventário inicial e a migração validada do armazenamento Docker/containerd após reboot. A migração teve como objetivo liberar a pequena partição raiz e preparar capacidade para MongoDB, Redis e testes de recovery.

A nova partição permanece no mesmo disco físico do sistema; ela amplia capacidade, mas não representa destino externo seguro de backup.
