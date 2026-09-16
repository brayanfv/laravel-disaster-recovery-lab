# Fail2Ban — TESTE-DEPLOY

## Instalação e estado

- Tipo: Host
- Versão: 1.0.2
- Serviço: ativo
- Jails ativos: 1
- Jail ativo: `sshd`

## Jail ativo

| Jail | Filtro | Serviço/porta protegida | Log monitorado | Falhas atuais | Banimentos atuais | Ação |
|---|---|---|---|---:|---:|---|
| `sshd` | `sshd` (perfil herdado) | `ssh` | `/var/log/auth.log` | 0 | 0 | `iptables-multiport` |

O jail `sshd` não possui falhas acumuladas nem IPs banidos no momento da consulta.

## Configuração efetiva identificada

| Parâmetro | Valor efetivo | Fonte da confirmação |
|---|---|---|
| `bantime` | 600 segundos (10 minutos) | `fail2ban-client get sshd bantime` |
| `findtime` | 600 segundos (10 minutos) | `fail2ban-client get sshd findtime` |
| `maxretry` | 5 | `fail2ban-client get sshd maxretry` |
| Log monitorado | `/var/log/auth.log` | `fail2ban-client status sshd` e `get sshd logpath` |
| Ação | `iptables-multiport` | `fail2ban-client get sshd actions` |

O comando de consulta do backend retornou que essa ação ainda não é implementada pelo cliente. A configuração declarada contém `backend = auto` em `jail.local` e `backend = systemd` em `jail.d/defaults-debian.conf`, mas o backend efetivo permanece pendente de confirmação.

## Arquivos identificados

| Item | Classificação preliminar | Observação |
|---|---|---|
| Fail2Ban | Software reconstruível | Pacote instalado no host. |
| `/etc/fail2ban/fail2ban.conf` | Arquivo padrão do pacote | Pertence ao pacote `fail2ban`. |
| `/etc/fail2ban/jail.conf` | Arquivo padrão do pacote | Pertence ao pacote `fail2ban`. |
| `/etc/fail2ban/jail.d/defaults-debian.conf` | Arquivo padrão do pacote | Pertence ao pacote `fail2ban`; declara `backend = systemd` e habilita `sshd`. |
| `/etc/fail2ban/jail.local` | Configuração personalizada | Não pertence ao pacote; define parâmetros padrão e habilita `sshd`. |
| `/etc/fail2ban/filter.d/sshd.conf` | Filtro padrão do pacote | Perfil utilizado pelo jail `sshd` por herança. |
| `/etc/fail2ban/filter.d/nginx-req-limit.conf` | Filtro personalizado | Não pertence ao pacote; não há jail Nginx ativo no momento. |
| Demais arquivos `filter.d/*.conf` | Arquivos padrão do pacote | Não foram identificados outros filtros fora do pacote. |
| Arquivos `action.d/*.conf` | Arquivos padrão do pacote | Não foram identificadas ações fora do pacote. |
| `paths-*.conf` e configurações auxiliares | Arquivos padrão ou de configuração base | Presentes sob `/etc/fail2ban`; conteúdo não inspecionado além do necessário. |

Não existem arquivos adicionais em `jail.d` além de `defaults-debian.conf`. Não foram identificados filtros com extensão `.local`.

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| Fail2Ban | Software reconstruível | Reinstalar o pacote e validar a versão necessária. |
| `/etc/fail2ban/jail.local` | Configuração personalizada | Preservar ou reproduzir os parâmetros e jails validados. |
| Jail `sshd` efetivo | Configuração reproduzível/documentável | Reproduzir `bantime`, `findtime`, `maxretry`, log e ação documentados. |
| `/etc/fail2ban/filter.d/nginx-req-limit.conf` | Configuração personalizada | Inspecionar e validar antes de reproduzir. |
| Arquivos padrão do pacote | Reconstruível | Restaurados pela reinstalação do pacote; comparar antes de qualquer customização. |

## Pendências

- Confirmar o backend efetivo do jail `sshd` por método suportado pelo Fail2Ban ou por inspeção controlada da configuração.
- Inspecionar o propósito e o conteúdo relevante de `filter.d/nginx-req-limit.conf` antes de habilitar ou reproduzir um jail Nginx.
- Verificar se existe configuração de ação adicional para `iptables-multiport` além do comportamento padrão do pacote.
- Avaliar futuramente se a ação por `iptables-multiport` deve permanecer alinhada à política de UFW; nenhuma alteração foi proposta ou executada.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento do Fail2Ban no ambiente `TESTE-DEPLOY`.

Nenhuma jail, filtro, ação, banimento, arquivo de configuração ou serviço foi alterado durante este levantamento.
