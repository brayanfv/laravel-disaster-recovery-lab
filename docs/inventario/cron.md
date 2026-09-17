# Cron — TESTE-DEPLOY

## Instalação e estado

- Tipo: Host
- Pacote: `cron` 3.0pl1-184ubuntu2
- Serviço: ativo e em execução
- Unidade systemd: `/usr/lib/systemd/system/cron.service`
- Crontab do usuário `lucas-cooperja`: presente; contém o disparo do Laravel Scheduler a cada minuto
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

- Laravel Scheduler: o crontab de `lucas-cooperja` executa a cada minuto a linha abaixo:

  ```cron
  * * * * * cd /home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy && CACHE_STORE=file /usr/bin/php artisan schedule:run >> /dev/null 2>&1
  ```

  - Usuário de execução: `lucas-cooperja` (não `root`).
  - PHP: `/usr/bin/php` (PHP CLI 8.3.6).
  - Projeto: `/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy`.
  - `CACHE_STORE=file` vale somente para esse processo; `.env` e a configuração global Laravel não foram alterados.
  - `stdout` e `stderr` são direcionados para `/dev/null`.
  - A integração Cron → Laravel Scheduler → tarefa agendada foi validada: a contagem do marcador `DR_TEST_SCHEDULER_001` em `storage/app/private/scheduler-dr-test.log` cresceu de 3 para 7 ocorrências.
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
| Crontab de `lucas-cooperja` | Configuração personalizada de usuário | Dispara o Laravel Scheduler a cada minuto com cache de filesystem temporário. |
| Crontab de `root` | Configuração de usuário | Ausente no momento do levantamento. |

## Pendências

- Confirmar se `/etc/cron.d/sendmail` foi criado por instalação local, configuração manual ou mecanismo externo ao banco de pacotes.
- Verificar, em futuro levantamento separado, timers systemd que possam substituir tarefas de Cron no host.
- Definir posteriormente qualquer estratégia de versionamento, backup ou recuperação; nenhuma foi definida neste documento e não há job de backup instalado.

## Situação atual

Este documento registra o inventário inicial e a integração posterior, validada, entre o Cron do usuário `lucas-cooperja` e o Laravel Scheduler. Não há job de backup e nenhum backup ou restore foi implementado neste documento.
