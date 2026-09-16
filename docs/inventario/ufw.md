# UFW — TESTE-DEPLOY

## Instalação e estado

- Tipo: Host
- Versão identificada anteriormente: 0.36.2
- Estado: ativo
- Logging: ativo (`low`)
- Novos perfis de aplicação: `skip`

## Políticas padrão

- Entrada: `deny`
- Saída: `allow`
- Tráfego roteado: `deny`

## Regras identificadas

| Nº | IP | Direção | Porta/protocolo ou perfil | Origem | Observação |
|---:|---|---|---|---|---|
| 1 | IPv4 | Entrada | `22/tcp` | Anywhere | SSH liberado para qualquer origem |
| 2 | IPv4 | Saída | `22/tcp` | Anywhere | Regra explícita; a política padrão de saída já é `allow` |
| 3 | IPv4 | Entrada | `Nginx HTTP` (`80/tcp`) | Anywhere | HTTP liberado para qualquer origem |
| 4 | IPv6 | Entrada | `22/tcp` | Anywhere | SSH liberado para qualquer origem IPv6 |
| 5 | IPv6 | Saída | `22/tcp` | Anywhere | Regra explícita; a política padrão de saída já é `allow` |
| 6 | IPv6 | Entrada | `Nginx HTTP` (`80/tcp`) | Anywhere | HTTP liberado para qualquer origem IPv6 |

Não foram identificadas restrições de origem nas regras listadas. As únicas portas de entrada liberadas são `22/tcp` e `80/tcp`, para IPv4 e IPv6.

## Arquivos identificados

| Arquivo | Classificação preliminar | Observação |
|---|---|---|
| `/etc/ufw/ufw.conf` | Configuração efetiva | Arquivo principal de comportamento do UFW; pode conter configuração local. |
| `/etc/ufw/user.rules` | Configuração efetiva/reproduzível | Armazena regras IPv4 persistidas pelo UFW. |
| `/etc/ufw/user6.rules` | Configuração efetiva/reproduzível | Armazena regras IPv6 persistidas pelo UFW. |
| `/etc/ufw/before.rules` e `/etc/ufw/before6.rules` | Configuração base | Arquivos canônicos do UFW; podem receber regras adicionais antes das regras do usuário. |
| `/etc/ufw/after.rules` e `/etc/ufw/after6.rules` | Configuração base | Arquivos canônicos do UFW; podem receber regras adicionais após as regras do usuário. |
| `/etc/ufw/before.init` e `/etc/ufw/after.init` | Configuração de inicialização | Arquivos canônicos para hooks de inicialização; conteúdo ainda não inspecionado. |
| `/etc/ufw/sysctl.conf` | Configuração de rede | Arquivo canônico do UFW; pode conter ajustes locais de kernel/rede. |
| `/etc/ufw/applications.d/openssh-server` | Perfil de aplicação, aparentemente padrão | Perfil OpenSSH instalado no host. |
| `/etc/ufw/applications.d/nginx` | Perfil de aplicação, aparentemente padrão | Perfil Nginx usado pela regra `Nginx HTTP`. |
| `/etc/ufw/applications.d/cups` | Perfil de aplicação, aparentemente padrão | Perfil CUPS presente; não há regra CUPS identificada. |

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| UFW | Software reconstruível | Reinstalar o pacote e validar a versão necessária. |
| `/etc/ufw/ufw.conf` | Configuração | Preservar ou reproduzir após validar o conteúdo. |
| `/etc/ufw/user.rules` | Configuração reproduzível/documentável | Reproduzir as regras IPv4 documentadas. |
| `/etc/ufw/user6.rules` | Configuração reproduzível/documentável | Reproduzir as regras IPv6 documentadas. |
| `before*.rules`, `after*.rules`, `before.init`, `after.init`, `sysctl.conf` | Configuração | Comparar com os padrões do pacote antes de classificar qualquer personalização. |
| Perfis em `applications.d/` | Configuração/perfis de pacote | Validar procedência e necessidade dos perfis antes de reproduzi-los. |

## Pendências

- Inspecionar somente as diretivas relevantes de `ufw.conf`, `user.rules` e `user6.rules` para confirmar a persistência das regras documentadas.
- Comparar `before*.rules`, `after*.rules`, arquivos `.init` e `sysctl.conf` com os padrões da versão instalada para identificar customizações.
- Confirmar a procedência dos perfis em `applications.d/` com o banco de arquivos do pacote.
- Validar futuramente se a regra explícita de saída `22/tcp` é intencional, já que a política padrão de saída é `allow`.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento do UFW no ambiente `TESTE-DEPLOY`.

Nenhuma regra, arquivo de configuração ou serviço do UFW foi alterado durante este levantamento.
