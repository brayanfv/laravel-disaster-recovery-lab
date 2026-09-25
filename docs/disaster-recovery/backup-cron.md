# Cron e monitoramento básico do backup — TESTE-DEPLOY

## Objetivo

`scripts/disaster-recovery/run-backup-cron.sh` prepara o ambiente reduzido do Cron e inicia o orquestrador `scripts/disaster-recovery/backup.sh`. O wrapper não duplica lógica de backup: o orquestrador continua responsável pelos cinco componentes, pelo `RUN_ID`, pelo lock, pelo manifesto, pela promoção e pela retenção.

O wrapper foi validado manualmente e pelo daemon Cron no laboratório. A entrada diária de Cron está instalada para o usuário `lucas-cooperja`, e o serviço `cron` está ativo (`active (running)`).

## Executor e ambiente

O wrapper deve ser executado pelo usuário `lucas-cooperja`. Ele confirma esse usuário, define `HOME` como `/home/lucas-cooperja` e fixa o seguinte `PATH`, sem depender do ambiente interativo:

```text
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

Antes de chamar `backup.sh`, ele verifica a disponibilidade de `bash`, `docker`, `ssh`, `scp`, `sha256sum`, `flock`, `tar`, `stat` e `chmod`.

Para garantir uma execução geral nova, o wrapper remove somente do seu ambiente os valores herdados de `RUN_ID` e `DR_ORCHESTRATED`. O `RUN_ID` é então gerado por `backup.sh`.

## Referências protegidas

O wrapper somente referencia arquivos externos ao repositório; ele não contém nem imprime seus conteúdos:

| Finalidade | Caminho | Validação do wrapper |
|---|---|---|
| Opções de autenticação MySQL | `/home/lucas-cooperja/.config/teste-deploy/mysql-backup.cnf` | Arquivo regular, sem link simbólico, legível e pertencente ao executor, modo `600` |
| Senha do backup MongoDB | `/home/lucas-cooperja/.config/teste-deploy/mongodb-backup-password` | Arquivo regular, sem link simbólico, legível e pertencente ao executor, modo `600` |
| Chave SSH dedicada | `/home/lucas-cooperja/.ssh/id_ed25519_backup_lab` | Arquivo regular, sem link simbólico, legível e pertencente ao executor, modo `600` |

O wrapper exporta apenas os nomes das variáveis esperadas por `backup.sh` e seus componentes: `MYSQL_BACKUP_DEFAULTS_FILE`, `MONGODB_BACKUP_PASSWORD_FILE` e `BACKUP_SSH_KEY`. Senhas, chaves e conteúdos de arquivos protegidos não podem ser adicionados a logs, argumentos ou Git.

## Logs e resultado

O wrapper adiciona (`append`) stdout e stderr ao log operacional:

```text
/srv/teste-deploy-data/backup-logs/cron-backup.log
```

O arquivo recebe modo `600`; o wrapper não o sobrescreve. Cada execução geral também continua gerando seu log próprio em:

```text
/srv/teste-deploy-data/backup-logs/<RUN_ID>-backup.log
```

O exit code de `backup.sh` é preservado. O log operacional registra o início e o resultado do wrapper, enquanto o log por `RUN_ID` registra componentes, lock, retenção, promoção, sucesso ou falha e duração.

## Crontab instalado

O horário continua sendo uma escolha de laboratório a ser revista conforme a operação real. A seguinte linha está instalada no crontab do usuário `lucas-cooperja` para executar diariamente às 02:00:

```cron
0 2 * * * /home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy/scripts/disaster-recovery/run-backup-cron.sh
```

O redirecionamento não precisa constar da linha: o wrapper já adiciona stdout e stderr em `cron-backup.log`. A entrada usa o crontab do usuário, não `sudo` nem o crontab de `root`.

## Validação manual do wrapper

O mesmo usuário executou manualmente o wrapper e validou a execução geral `2026-09-24_173106`:

- lock global adquirido;
- MySQL, MongoDB, Redis, Laravel storage e Portainer concluídos com sucesso;
- manifesto global validado e promoção final concluída;
- retenção concluída;
- `Backup geral SUCCESS` e `Wrapper de Cron concluído; status=SUCCESS` registrados.

O teste confirmou também o append em `/srv/teste-deploy-data/backup-logs/cron-backup.log`, os logs separados por `RUN_ID` e componente, e o monitoramento manual por `grep`, `tail` e `ls`. Os logs observados possuem permissões restritivas.

## Monitoramento básico por logs

Os comandos abaixo não dependem de ferramentas externas e não exibem secrets:

```bash
tail -n 100 /srv/teste-deploy-data/backup-logs/cron-backup.log
grep -E 'Backup geral (SUCCESS|FAILED)|Wrapper de Cron concluído' /srv/teste-deploy-data/backup-logs/cron-backup.log
grep -F 'Outro backup geral já está em execução' /srv/teste-deploy-data/backup-logs/cron-backup.log
grep -E 'Componente .*falhou|Retenção remota|duration=' /srv/teste-deploy-data/backup-logs/cron-backup.log
find /srv/teste-deploy-data/backup-logs -maxdepth 1 -type f -name '*-backup.log' -printf '%f\n' | sort
```

- `Backup geral SUCCESS` e `Wrapper de Cron concluído; status=SUCCESS` confirmam sucesso do orquestrador e do wrapper.
- `Backup geral FAILED`, `status=FAILED` ou `Componente ... falhou` indicam falha e devem ser investigados no log do `RUN_ID` correspondente.
- `Outro backup geral já está em execução` indica recusa pelo `flock`; a segunda execução não deve criar staging remoto nem executar componentes.
- Linhas `Retenção remota:` registram quantidade de restore points, remoções válidas e resultado da retenção.
- `duration=` no log por `RUN_ID` registra a duração total da execução geral.

Para verificar somente metadados dos arquivos protegidos, sem ler conteúdo:

```bash
stat -c '%n | %U:%G | %a | %F' \
  /home/lucas-cooperja/.config/teste-deploy/mysql-backup.cnf \
  /home/lucas-cooperja/.config/teste-deploy/mongodb-backup-password \
  /home/lucas-cooperja/.ssh/id_ed25519_backup_lab
```

## Validação da execução agendada pelo daemon

O teste original das 02:00 de 2026-09-25 não ocorreu porque o host e o serviço Cron só estavam ativos a partir de aproximadamente 13:22. Isso não foi falha do wrapper, do orquestrador ou dos componentes.

Para validar o daemon de modo controlado, o horário foi temporariamente alterado para 16:05. O Cron disparou automaticamente às 16:05:01 e executou:

```text
/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy/scripts/disaster-recovery/run-backup-cron.sh
```

O `RUN_ID` gerado foi `2026-09-25_160501`. MySQL, MongoDB, Redis, Laravel storage e Portainer concluíram com `SUCCESS`; o manifesto global foi criado e validado remotamente; o restore point foi promovido para `/srv/backups/teste-deploy/2026-09-25_160501`; e a retenção terminou com `SUCCESS`.

O log registrou `Backup geral SUCCESS` e `Wrapper de Cron concluído; status=SUCCESS`. No destino externo, `sha256sum -c manifest.sha256` retornou sucesso para os cinco artefatos. Portanto, a **execução automática do backup via daemon Cron está validada**.

## Limitações e pendências

- Não há alertas externos, rotação automática de logs, monitoramento ativo ou restore automatizado.
- A estratégia definitiva de secrets permanece pendente. A recuperação manual em máquina limpa foi validada, mas o pipeline de backup desse novo host ainda precisaria ser reprovisionado antes de ativar seu Cron de backup.
- Cron tradicional não executa retroativamente uma tarefa perdida enquanto o host ou o serviço estiver desligado. Avaliar futuramente `systemd timer` persistente ou mecanismo equivalente para a política de recuperação de execuções perdidas.
