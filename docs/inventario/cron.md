# Cron — TESTE-DEPLOY

## Instalação e estado

- Tipo: Host
- Pacote: `cron` 3.0pl1-184ubuntu2
- Serviço: ativo e em execução
- Unidade systemd: `/usr/lib/systemd/system/cron.service`
- Crontab do usuário `lucas-cooperja`: inexistente
- Crontab do `root`: inexistente

## Agendamentos do sistema

| Origem | Periodicidade declarada | Usuário | Comando/objetivo aparente | Classificação |
|---|---|---|---|---|
| `/etc/crontab` | Minuto 17 de cada hora | `root` | Executa `run-parts` em `/etc/cron.hourly` | Padrão do pacote |
| `/etc/crontab` | Diariamente, 06:25 | `root` | Executa `run-parts` em `/etc/cron.daily` somente sem Anacron | Padrão do pacote |
| `/etc/crontab` | Domingos, 06:47 | `root` | Executa `run-parts` em `/etc/cron.weekly` somente sem Anacron | Padrão do pacote |
| `/etc/crontab` | Dia 1, 06:52 | `root` | Executa `run-parts` em `/etc/cron.monthly` somente sem Anacron | Padrão do pacote |
| `/etc/cron.d/anacron` | A cada hora entre 07:30 e 23:30 | `root` | Inicia Anacron como fallback, somente sem systemd | Padrão do pacote `anacron` |
| `/etc/cron.d/certbot` | A cada 12 horas | `root` | Renovação não interativa de certificados Certbot, somente sem systemd | Padrão do pacote `certbot` |
| `/etc/cron.d/e2scrub_all` | Domingo, 03:30; diariamente, 03:10 | `root` | Manutenção/verificação de sistemas de arquivos ext4, somente sem systemd | Padrão do pacote `e2fsprogs` |
| `/etc/cron.d/php` | Minutos 09 e 39 de cada hora | `root` | Limpeza de sessões PHP, somente sem systemd | Padrão do pacote `php-common` |
| `/etc/cron.d/sendmail` | A cada 20 minutos | `smmsp` | Processamento/manutenção da fila Sendmail (`cron-msp`) | Configuração local/personalizada |

As tarefas marcadas como fallback verificam a presença de `/run/systemd/system`; como o host usa systemd, essas linhas não executam sua ação por Cron nas condições atuais.

## Tarefas em diretórios `run-parts`

| Diretório | Arquivos identificados | Classificação |
|---|---|---|
| `/etc/cron.hourly` | Nenhuma tarefa além de `.placeholder` | Sem job operacional identificado |
| `/etc/cron.daily` | `0anacron`, `apt-compat`, `aptitude`, `dpkg`, `logrotate`, `man-db`, `plocate`, `sendmail` | Arquivos pertencentes a pacotes instalados |
| `/etc/cron.weekly` | `0anacron`, `man-db` | Arquivos pertencentes a pacotes instalados |
| `/etc/cron.monthly` | `0anacron` | Arquivo pertencente a pacote instalado |

## Aplicação, backup e manutenção

- Laravel Scheduler: não identificado. Não há `Schedule::` ou `schedule:run` no projeto, nem job Laravel nos agendamentos visíveis.
- Backup: não foi identificado job de backup.
- Docker, bancos e Nginx: não há job específico identificado em crontabs ou em `/etc/cron.d`.
- Logs: `logrotate` está presente como tarefa diária fornecida por pacote.
- Manutenção: há tarefas de pacotes para sessões PHP, Anacron, certificados, sistemas de arquivos, APT, `logrotate`, índices `plocate` e Sendmail.

## Classificação preliminar

| Item | Tipo | Tratamento futuro provável |
|---|---|---|
| Cron | Software reconstruível | Reinstalar o pacote e validar a versão necessária. |
| `/etc/crontab` | Configuração do sistema | Restaurada pelo pacote; validar alterações antes de reproduzir. |
| Arquivos pertencentes a pacotes em `/etc/cron.d` e diretórios `cron.*` | Tarefas reconstruíveis | Restauradas pela reinstalação dos respectivos pacotes. |
| `/etc/cron.d/sendmail` | Configuração personalizada | Validar origem e necessidade antes de reproduzir. |
| Job `cron-msp` | Tarefa reproduzível/documentável | Reproduzir somente se o Sendmail e a fila SMTP fizerem parte do ambiente-alvo. |
| Crontabs de `lucas-cooperja` e `root` | Configuração de usuário | Ausentes no momento do levantamento. |

## Pendências

- Confirmar se `/etc/cron.d/sendmail` foi criado por instalação local, configuração manual ou mecanismo externo ao banco de pacotes.
- Verificar, em futuro levantamento separado, timers systemd que possam substituir tarefas de Cron no host.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento.

## Situação atual

Este documento representa somente o mapeamento do Cron no ambiente `TESTE-DEPLOY`.

Nenhum agendamento, arquivo, serviço ou job foi criado, alterado, executado, reiniciado ou removido durante este levantamento.
