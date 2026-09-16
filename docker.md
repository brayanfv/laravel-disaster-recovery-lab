# Docker — TESTE-DEPLOY

## Instalação e estado

- Tipo: Host
- Docker Engine: 29.1.3
- Docker Compose: 2.40.3
- Serviço Docker: ativo
- Containers: 1 em execução e 3 parados
- Imagens locais: 3
- Volumes nomeados: 1
- Networks: 3, todas padrão do Docker

## Containers

| Container | Imagem | Estado no levantamento | Restart policy | Labels Compose | Mounts | Classificação preliminar |
|---|---|---|---|---|---|---|
| `portainer` | `portainer/portainer-ce:latest` | Em execução | `always` | Ausentes | Volume `portainer_data` em `/data`; bind do socket Docker | Serviço com estado persistente |
| `objective_beaver` | `hello-world:latest` | Parado, saída 0 há cerca de 2 semanas | `no` | Ausentes | Nenhum | Teste descartável |
| `priceless_rubin` | `ubuntu:latest` | Parado há cerca de 2 semanas | `no` | Ausentes | Nenhum | Aparentemente teste descartável |
| `trusting_margulis` | `hello-world:latest` | Parado, saída 0 há cerca de 2 semanas | `no` | Ausentes | Nenhum | Teste descartável |

Todos os containers têm `com.docker.compose.project` e `com.docker.compose.service` vazios. Não há containers associados a um projeto Compose identificado.

## Imagens relevantes

| Imagem | Tag | ID curto | Tamanho | Classificação preliminar |
|---|---|---|---:|---|
| `portainer/portainer-ce` | `latest` | `511f3f06c96f` | 201 MB | Imagem reconstruível/downloadable; tag não fixada por versão |
| `ubuntu` | `latest` | `2260313b31c8` | 160 MB | Imagem reconstruível/downloadable; usada apenas por container parado de teste |
| `hello-world` | `latest` | `5dd0d3e6e255` | 25,9 kB | Imagem reconstruível/downloadable; usada apenas por testes |

## Networks

| Network | Driver | Scope | Tipo | Uso identificado |
|---|---|---|---|---|
| `bridge` | `bridge` | `local` | Padrão Docker | Network do container `portainer` |
| `host` | `host` | `local` | Padrão Docker | Nenhum container associado identificado |
| `none` | `null` | `local` | Padrão Docker | Nenhum container associado identificado |

## Volumes e mounts

| Recurso | Tipo | Origem no host | Destino no container | Estado/classificação |
|---|---|---|---|---|
| `portainer_data` | Volume nomeado, driver `local` | `/var/lib/docker/volumes/portainer_data/_data` | `/data` no `portainer` | Dado persistente |
| Socket Docker | Bind mount | `/var/run/docker.sock` | `/var/run/docker.sock` no `portainer` | Integração/configuração do container; leitura e escrita habilitadas |

O volume `portainer_data` foi criado em 28/08/2026, não possui labels nem opções declaradas e tem escopo `local`.

Os containers de teste não possuem volume nomeado, bind mount ou mount `tmpfs` identificado.

## Docker Compose

`docker compose ls --all` não apresentou projeto com status e arquivos de configuração preenchidos. Somado à ausência de labels Compose nos containers, não há recurso em execução associado a Docker Compose neste levantamento.

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| Docker Engine e Compose | Software reconstruível | Reinstalar versões compatíveis e validar o daemon. |
| Imagens locais | Imagens reconstruíveis/downloadable | Baixar novamente por tag ou, preferencialmente, por versão/digest definido. |
| Container `portainer` | Container reconstruível | Recriar com os mounts, rede, porta e política de restart documentados. |
| Volume `portainer_data` | Dado persistente | Preservar e validar o conteúdo antes de qualquer ação futura. |
| Bind `/var/run/docker.sock` | Configuração de integração | Recriar somente se Portainer continuar administrando o daemon local. |
| Containers `hello-world` e `ubuntu` parados | Recursos descartáveis de teste | Não possuem estado persistente identificado. |
| Networks `bridge`, `host` e `none` | Recursos padrão reconstruíveis | Fornecidos pelo Docker. |

## Pendências

- Determinar uma versão ou digest fixo para a imagem do Portainer, pois atualmente é usada a tag `latest`.
- Inspecionar o conteúdo funcional de `portainer_data` somente se necessário para um inventário de dados posterior.
- Validar se a linha sem status/arquivos retornada por `docker compose ls --all` representa metadado residual ou projeto incompleto; ela não está associada a containers por labels.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento do Docker no ambiente `TESTE-DEPLOY`.

Nenhum container, imagem, volume, network ou projeto Compose foi criado, alterado, iniciado, parado, removido ou limpo durante este levantamento.
