# Nginx — TESTE-DEPLOY

## Instalação

- Tipo: Host
- Versão: 1.24.0
- Serviço: ativo
- Porta: TCP 80

## Configuração principal

`/etc/nginx/nginx.conf`

## Virtual host da aplicação

`/etc/nginx/sites-available/teste.local`

Ativação:

`/etc/nginx/sites-enabled/teste.local`

O arquivo em `sites-enabled` é um link simbólico para o arquivo localizado em `sites-available`.

## Aplicação atendida

Server name:

`172.23.1.132`

Document root:

`/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy/public`

## PHP

- PHP-FPM: 8.3
- Socket: `/var/run/php/php8.3-fpm.sock`

## HTTPS

Não identificado/configurado no momento.

O virtual host atual escuta apenas na porta 80.

## Configurações customizadas identificadas

### Rate limiting

O arquivo `/etc/nginx/nginx.conf` possui configurações customizadas:

- `login_limit`: 3 requisições por segundo
- `geral_limit`: 30 requisições por segundo

### Virtual host

`/etc/nginx/sites-available/teste.local`

é específico da aplicação Laravel e deve ser tratado como configuração própria do ambiente.

### Logs da aplicação

- `/var/log/nginx/laravel_access.log`
- `/var/log/nginx/laravel_error.log`

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| Nginx | Software reconstruível | Reinstalar |
| `/etc/nginx/nginx.conf` | Configuração customizada | Preservar/versionar |
| `/etc/nginx/sites-available/teste.local` | Configuração customizada | Preservar/versionar |
| `/etc/nginx/sites-enabled/teste.local` | Link simbólico reconstruível | Recriar |
| Arquivos padrão do Nginx | Reconstruível | Reinstalação do pacote |
| Logs | Dados operacionais | Avaliar retenção; não essenciais ao restore básico |

## Pendências

- Verificar os dois blocos `location ~ \.php$` presentes no virtual host.
- Verificar se `login_limit` deveria ser aplicado somente ao login.
- Verificar se `geral_limit` está sendo utilizado.
- Decidir futuramente se HTTPS será configurado neste laboratório.
- Definir posteriormente quais configurações serão versionadas e quais participarão da estratégia de backup.
- Criar procedimento de restauração somente depois que a arquitetura de backup estiver definida.

## Situação atual

Este documento representa somente o mapeamento do Nginx no ambiente `TESTE-DEPLOY`.

Ainda não foi definida nem implementada uma estratégia de backup ou recuperação.
