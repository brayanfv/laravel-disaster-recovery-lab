# Portainer — TESTE-DEPLOY

## Instalação e estado

- Tipo: Container Docker no host
- Nome do container: `portainer`
- Imagem: `portainer/portainer-ce:latest`
- Estado no levantamento: em execução
- Política de restart: `always`
- Comando configurado no container: não há sobrescrita de `Cmd` (`null`); a imagem usa sua configuração padrão.

## Rede e portas

- Network: `bridge`
- Porta publicada: `9443/tcp`
  - `0.0.0.0:9443`
  - `[::]:9443`
- Portas internas não publicadas: `8000/tcp` e `9000/tcp`.

## Mounts

| Tipo | Origem | Destino | Permissão | Finalidade aparente |
|---|---|---|---|---|
| Volume nomeado | `/var/lib/docker/volumes/portainer_data/_data` | `/data` | Leitura e escrita | Dados persistentes do Portainer |
| Bind mount | `/var/run/docker.sock` | `/var/run/docker.sock` | Leitura e escrita | Administração do daemon Docker local |

O volume `portainer_data` usa driver `local`, escopo `local`, não possui labels nem opções declaradas e foi criado em 28/08/2026.

## Compose

Não há labels `com.docker.compose.project` ou `com.docker.compose.service` no container. Não há projeto Compose associado ao Portainer identificado; as evidências indicam criação por `docker run` ou mecanismo equivalente, e não por Docker Compose.

## Configuração relevante

- O container usa uma imagem com tag `latest`, sem versão ou digest fixado no levantamento.
- O bind mount do socket Docker fornece acesso de leitura e escrita ao daemon local; isso é necessário para a função de administração, mas deve ser tratado como configuração de alto privilégio.
- O estado funcional do Portainer reside no volume `portainer_data`; o container e a imagem são reconstruíveis separadamente.

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| Container `portainer` | Container reconstruível | Recriar com imagem, porta, network, mounts e restart policy documentados. |
| `portainer/portainer-ce:latest` | Imagem reconstruível/downloadable | Baixar versão/digest definido em futura decisão. |
| `portainer_data` | Dado persistente | Preservar e validar antes de qualquer ação futura. |
| Bind do socket Docker | Configuração | Reproduzir somente se a administração do daemon local for necessária. |
| Network `bridge` | Recurso padrão reconstruível | Disponibilizado pelo Docker. |

## Pendências

- Definir futuramente a versão ou digest de Portainer desejado, evitando depender de `latest`.
- Verificar, somente se necessário, os dados funcionais armazenados em `portainer_data`.
- Esclarecer o metadado sem status/arquivos listado por `docker compose ls --all`; ele não está vinculado ao Portainer.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento do Portainer no ambiente `TESTE-DEPLOY`.

Nenhuma configuração de Docker ou Portainer foi alterada durante este levantamento.
