# Backup e restore manual do volume Portainer — TESTE-DEPLOY

## Objetivo

Registrar o fluxo manual validado de backup e restore do volume persistente `portainer_data`, incluindo a recuperação funcional do estado configurado do Portainer.

## Pré-requisitos e estado original

| Item | Estado confirmado |
|---|---|
| Container original | `portainer` |
| Imagem configurada | `portainer/portainer-ce:latest` |
| Porta HTTPS original | `9443` no host |
| Volume persistente | `portainer_data` |
| Destino do volume no container | `/data` |
| Socket Docker | `/var/run/docker.sock` |
| Mountpoint observado | `/srv/teste-deploy-data/docker/volumes/portainer_data/_data` |
| Staging local do backup configurado | `/srv/teste-deploy-data/backup-staging/portainer` |
| Destino externo | `teste@172.23.1.115:/srv/backups/teste-deploy/` |

O volume continha os nomes de diretórios e arquivos abaixo; nenhum conteúdo foi lido ou reproduzido:

```text
bin/
certs/
chisel/
compose/
portainer.db
portainer.key
portainer.pub
tls/
```

## Primeiro teste: estado inicial reproduzido

Um primeiro backup foi realizado antes da configuração inicial do Portainer. O restore desse estado em container isolado exibiu `New Portainer installation`.

Esse resultado foi inicialmente investigado como possível falha de restore. Posteriormente, foi confirmado que o Portainer original na porta 9443 ainda estava no mesmo estado de instalação inicial. Os logs do original registravam carregamento da base PortainerDB, emissão de setup token e timeout de segurança da instalação inicial.

Assim, o primeiro restore reproduziu corretamente o estado existente no momento do backup, mas não era suficiente para validar recuperação funcional de usuário ou configuração. Nenhum setup token é registrado neste documento.

## Validação funcional e segundo backup

O Portainer original foi inicializado com credenciais fictícias do laboratório e o acesso ao ambiente Docker local foi confirmado.

Também foi criado o container marcador `dr-portainer-marker` com a label `dr.marker=DR_TEST_PORTAINER_001`, visível na interface do Portainer original.

> A presença desse container depois de um restore não é, isoladamente, prova de persistência da base Portainer. O Portainer restaurado usa o mesmo `/var/run/docker.sock` e, por isso, enxerga os containers atuais do host.

Após a configuração funcional, o Portainer original foi parado de forma controlada e foi criado o artefato:

```text
/srv/teste-deploy-data/backup-staging/portainer/portainer_data_configured.tar.gz
```

Também foi criado o checksum `portainer_data_configured.tar.gz.sha256`.

## Integridade e transferência

O archive e o checksum foram enviados por SCP, usando a chave SSH dedicada, para `/srv/backups/teste-deploy/` na máquina externa.

A validação remota de integridade foi concluída com sucesso:

```text
portainer_data_configured.tar.gz: SUCESSO
```

## Restore funcional isolado validado

1. O container e o volume usados no primeiro teste de restore foram removidos antes do segundo teste.
2. O backup configurado foi baixado novamente da máquina externa e teve seu SHA-256 validado.
3. Foi criado o volume isolado `portainer_restore_test_data`.
4. O archive foi extraído no volume isolado.
5. Foi criado o container isolado `portainer-restore-test` com:
   - porta publicada `9444` → `9443`;
   - volume `portainer_restore_test_data:/data`;
   - bind mount `/var/run/docker.sock:/var/run/docker.sock`.
6. O Portainer restaurado abriu em `https://localhost:9444`.
7. Diferentemente do primeiro teste, a tela de instalação inicial não foi apresentada.
8. Foi possível autenticar com o usuário fictício que já existia no Portainer original antes do segundo backup.

A autenticação com esse usuário pré-existente é a evidência funcional principal de que o estado persistido em `portainer.db` foi recuperado.

O ambiente Docker local também ficou acessível e exibiu os containers atuais, incluindo `dr-portainer-marker`. Essa listagem depende do Docker socket e não deve ser usada sozinha como prova de restauração da base Portainer.

## Resultado final

Foram validados no laboratório:

- parada controlada do Portainer;
- backup manual de `portainer_data` em `tar.gz`;
- SHA-256 e transferência externa;
- validação remota e download do artefato;
- restore em volume novo e container Portainer isolado;
- recuperação funcional do estado configurado;
- autenticação com usuário existente antes do backup.

O teste manual originalmente descrito não validava esses pontos. Posteriormente, o volume foi restaurado em máquina limpa a partir do restore point `2026-09-24_173106`: `portainer.db` foi carregado e a autenticação com usuário existente no backup funcionou. O backup automatizado, o orquestrador, o manifesto, o lock e a retenção também foram implementados e validados separadamente.

## Gap técnico: imagem `latest`

O container original usa `portainer/portainer-ce:latest`. Para um disaster recovery reproduzível, a imagem deverá ser fixada por versão ou digest em etapa futura, em vez de depender de uma tag mutável. Essa configuração não foi alterada nesta etapa.

## Limitações e pendências

- Existem script de componente, orquestrador, manifesto, lock e retenção; restore automatizado ainda não existe.
- A nomenclatura por `RUN_ID` é aplicada pela execução geral.
- Monitoramento ativo/alertas permanecem pendentes.
- A estratégia de secrets e sua criptografia continuam pendentes.
- O restore manual em máquina limpa foi validado; a imagem `latest` introduziu migração de banco e reforça a necessidade de pin de versão/digest.
- Backup e restore de uploads públicos, caso existam, permanecem pendentes.
- A estratégia definitiva de versão/digest do Portainer permanece pendente.

## Situação atual

Este documento registra somente o fluxo manual Portainer já validado. Nenhuma credencial, setup token, chave privada ou conteúdo de chave foi exposto, e nenhuma configuração de Portainer foi alterada por esta documentação.
