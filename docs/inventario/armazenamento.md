# Armazenamento do laboratório — TESTE-DEPLOY

## Objetivo

Esta partição foi adicionada para disponibilizar capacidade local ao laboratório `TESTE-DEPLOY`, cujo filesystem raiz possui aproximadamente 15,8 GB e havia atingido uma condição crítica de uso.

## Partição e montagem

| Item | Valor |
|---|---|
| Disco físico | `/dev/nvme0n1` |
| Partição | `/dev/nvme0n1p6` |
| Filesystem | `ext4` |
| Label | `teste-deploy-dat` |
| UUID | `53c168bc-a66a-4de0-826b-6816b025e1d8` |
| Tamanho aproximado | 30 GB |
| Espaço disponível confirmado | Aproximadamente 28 GB |
| Mountpoint | `/srv/teste-deploy-data` |

## Persistência da montagem

A montagem está configurada de forma persistente em `/etc/fstab` pela entrada abaixo:

```fstab
UUID=53c168bc-a66a-4de0-826b-6816b025e1d8 /srv/teste-deploy-data ext4 defaults 0 2
```

As validações informadas foram concluídas sem erro:

- `sudo mount -a`;
- `findmnt`, confirmando o mountpoint;
- `df -hT`, confirmando o filesystem `ext4` e a capacidade.
- reboot de validação, confirmando montagem automática via `/etc/fstab`.

## Layout relevante

`/dev/nvme0n1p6` é uma partição local do mesmo disco físico que contém o sistema. Ela fornece capacidade adicional montada separadamente e não amplia o filesystem raiz (`/`).

## Uso validado

O mountpoint passou a hospedar o armazenamento persistente de Docker e containerd:

| Componente | Localização atual |
|---|---|
| Docker data-root | `/srv/teste-deploy-data/docker` |
| Containerd root persistente | `/srv/teste-deploy-data/containerd` |
| Containerd state temporário | `/run/containerd` |
| Volume `portainer_data` | `/srv/teste-deploy-data/docker/volumes/portainer_data/_data` |
| Volume `mongodb_data` | Sob `/srv/teste-deploy-data/docker/volumes/` |

Após reboot, `containerd` e `docker` iniciaram ativos, o container Portainer subiu automaticamente e containers, imagens e volumes existentes permaneceram visíveis.

MongoDB passou a usar o volume persistente `mongodb_data` sob o data-root Docker. O uso da partição para Redis, dados fictícios adicionais e outros serviços do laboratório continua pendente de decisão específica.

## Origem e rollback temporário

As localizações anteriores foram:

- Docker: `/var/lib/docker`;
- containerd: `/var/lib/containerd`.

Essas origens foram mantidas temporariamente como opção de rollback e ainda não devem ser removidas.

## Limitações

- A partição está no mesmo disco físico do sistema; ela resolve capacidade local, mas não protege contra falha física, perda ou indisponibilidade desse disco/servidor.
- Ela não é, por si só, um destino seguro ou externo para backups.
- A definição do destino real de backups, retenção e cópia em segunda máquina permanece pendente.
- Serviços que gravam em caminhos padrão da raiz continuam dependendo da capacidade da raiz até que haja uma decisão futura e documentada sobre seus caminhos de dados.

## Classificação preliminar

| Item | Classificação | Tratamento futuro provável |
|---|---|---|
| `/dev/nvme0n1p6` | Infraestrutura local persistente | Preservar e recriar/documentar em reconstrução de infraestrutura. |
| `/srv/teste-deploy-data` | Capacidade local do laboratório | Hospeda Docker/containerd; alocar novos serviços somente após decisão explícita. |
| `/srv/teste-deploy-data/docker` | Dado operacional persistente | Preservar; contém o data-root atual do Docker. |
| `/srv/teste-deploy-data/containerd` | Dado operacional persistente | Preservar; contém o root persistente atual do containerd. |
| `mongodb_data` | Dado persistente do MongoDB | Preservar; backup e restore permanecem pendentes. |
| `/var/lib/docker` e `/var/lib/containerd` | Rollback temporário | Não remover até decisão explícita posterior. |
| Armazenamento externo de backups | Pendente | Definir separadamente; não é atendido pela nova partição. |

## Situação atual

Este documento registra a capacidade de armazenamento e a migração validada de Docker/containerd. A definição do destino externo de backups e a estratégia de restore continuam pendentes.
