# Desenho da automação de backup — TESTE-DEPLOY

## Objetivo e escopo

Este documento define o desenho inicial da futura automação de backup do laboratório `TESTE-DEPLOY`. Ele se baseia nos fluxos manuais já validados para MySQL, MongoDB, Redis, `storage/app/private` e `portainer_data`.

Este é um documento de design. A primeira implementação incremental — backup local de MySQL — já existe e teve testes reais de sucesso e falha documentados em [backup-script-mysql.md](backup-script-mysql.md). Ainda não há agendamento, transferência automática, retenção automática ou restore automatizado. Os procedimentos manuais documentados continuam sendo a referência para os demais componentes.

## Princípios

- Cada execução completa deve ter um identificador único, artefatos autocontidos e um resultado inequívoco.
- Dados persistentes devem ser copiados para destino externo; o staging local não é um destino de disaster recovery.
- Falhas em componentes críticos devem impedir que a execução seja declarada válida.
- Senhas, conteúdos de `.env`, chaves privadas e tokens não podem ser incorporados a scripts, argumentos registrados em log ou manifests.
- Automação de backup e automação de restore são responsabilidades separadas. Este desenho não propõe um restore automático.

## Organização conceitual dos scripts

Quando a implementação for autorizada, a estrutura proposta é:

```text
scripts/disaster-recovery/
├── backup.sh
├── backup-mysql.sh
├── backup-mongodb.sh
├── backup-redis.sh
├── backup-laravel-storage.sh
├── backup-portainer.sh
└── lib/
    └── common.sh
```

- `backup.sh` será o orquestrador: cria o identificador único, prepara staging e logs, controla a ordem, consolida checksums, transfere a execução e define o resultado final.
- Cada `backup-<componente>.sh` será independente dentro do seu escopo, para permitir execução e diagnóstico isolados sem duplicar a lógica de todos os componentes.
- `lib/common.sh` deverá conter apenas funções realmente compartilhadas, como validação de diretórios, criação de logs, cálculo de checksum, transferência e tratamento uniforme de erros. Não deverá concentrar lógica específica de banco ou volume.
- Quando chamado por `backup.sh`, cada script de componente deverá usar o `RUN_ID` e os parâmetros de destino fornecidos pelo orquestrador, preservando a organização da execução completa.
- Quando executado isoladamente, um script de componente poderá gerar um `RUN_ID` próprio. Esse resultado será um artefato isolado do componente, não uma execução completa válida do sistema.

No estado atual, existem apenas `backup-mysql.sh` e `lib/common.sh`. `backup.sh`, os scripts dos demais componentes e os recursos de transferência, retenção e restore ainda são proposta e não existem.

## Identificador e estrutura de uma execução

O identificador proposto é um timestamp previsível no formato `YYYY-MM-DD_HHMMSS`, por exemplo `2026-09-18_230000`. Uma execução completa usará um único `RUN_ID` para todos os componentes.

O contrato do `RUN_ID` precisa distinguir dois casos:

- em uma execução completa, `backup.sh` gera o `RUN_ID` e o repassa a todos os scripts de componente;
- em uma execução isolada, o script do componente pode gerar um `RUN_ID` próprio, mas não pode anunciar seu diretório como restore point completo.

Essa distinção deverá orientar a seleção futura de restore points e a retenção: somente uma execução completa, promovida e validada no destino remoto poderá ser selecionada como restore point do sistema.

### Staging local

O staging proposto é:

```text
/srv/teste-deploy-data/backup-staging/<timestamp>/
├── mysql/
├── mongodb/
├── redis/
├── laravel-storage/
└── portainer/
```

Exemplo: `/srv/teste-deploy-data/backup-staging/2026-09-18_230000/`.

`/srv/teste-deploy-data/backup-staging` fica na mesma máquina e no mesmo dispositivo físico do host principal. Ele serve para geração, verificação e transferência temporária dos artefatos, mas não é um destino final de disaster recovery.

### Destino externo e promoção

A transferência deverá iniciar em um staging remoto que não represente um backup válido:

```text
/srv/backups/teste-deploy/.incomplete/<RUN_ID>/
```

Somente depois que todos os componentes críticos tiverem sucesso, `manifest.sha256` tiver sido criado, a transferência estiver completa e a validação remota de SHA-256 tiver sido concluída, a execução poderá ser promovida para o diretório definitivo:

```text
/srv/backups/teste-deploy/<RUN_ID>/
├── mysql/
├── mongodb/
├── redis/
├── laravel-storage/
├── portainer/
└── manifest.sha256
```

Quando staging e destino definitivo estiverem no mesmo filesystem remoto, a promoção poderá futuramente usar `rename`/`mv`, reduzindo o risco de expor uma cópia parcial no diretório final. A implementação ainda deverá validar esse pressuposto antes de depender dessa propriedade.

Exemplo de diretório promovido: `/srv/backups/teste-deploy/2026-09-18_230000/` na máquina externa atualmente acessada como `teste@172.23.1.115`. Esse IP é específico do laboratório e deverá ser parametrizável ou redescoberto em outros ambientes.

Somente diretórios promovidos/concluídos em `/srv/backups/teste-deploy/<RUN_ID>/` são restore points válidos. Diretórios em `.incomplete/`, incluindo transferências interrompidas ou falhas, servem apenas para diagnóstico e nunca devem ser apresentados como backup válido, selecionados para restore ou considerados pela retenção.

O diretório inteiro de uma execução promovida, e não arquivos individuais isolados, será a unidade de validade, retenção e futura remoção controlada.

## Artefatos propostos

Os formatos manuais já validados devem ser preservados inicialmente. O timestamp fica no diretório da execução; por isso os nomes não precisam repeti-lo sem uma justificativa futura.

| Componente | Subdiretório | Artefato proposto | Método manual de referência |
|---|---|---|---|
| MySQL | `mysql/` | `teste_deploy.sql` | `mysqldump` lógico validado |
| MongoDB | `mongodb/` | `teste_deploy_lab.archive` | `mongodump` em archive validado |
| Redis | `redis/` | `redis_data.tar.gz` | Archive do volume persistente validado |
| Laravel storage privado | `laravel-storage/` | `laravel-private-storage.tar.gz` | Archive de `storage/app/private` validado |
| Portainer | `portainer/` | `portainer_data.tar.gz` | Archive do volume `portainer_data` validado |

## Integridade

Cada artefato deverá ter checksum SHA-256 calculado com caminhos relativos à raiz da execução. Após a criação de todos os artefatos, a automação deverá gerar `manifest.sha256` na raiz da execução contendo os hashes dos artefatos da execução completa, por exemplo:

```text
<hash>  mysql/teste_deploy.sql
<hash>  mongodb/teste_deploy_lab.archive
<hash>  redis/redis_data.tar.gz
<hash>  laravel-storage/laravel-private-storage.tar.gz
<hash>  portainer/portainer_data.tar.gz
```

Arquivos `.sha256` individuais poderão continuar existindo para validação isolada de um componente, mas o `manifest.sha256` principal não precisa incluir checksum dos próprios arquivos de checksum.

O manifesto permite validar a execução como conjunto no staging e novamente no destino externo. SHA-256 confirma integridade dos bytes transferidos; ele não substitui uma cópia externa, não fornece criptografia e não elimina a necessidade de um restore de teste.

## Falhas, logs e resultado

### Política de falha

O comportamento proposto é *fail-fast*. Se um componente crítico falhar, a execução deverá:

- registrar o erro e o componente afetado;
- retornar código de saída diferente de zero;
- não ser declarada como backup completo ou válida para restore;
- preservar staging, logs e outras evidências necessárias ao diagnóstico, sem limpeza automática destrutiva.

Uma condição interna como `PARTIAL` ou `INCOMPLETE` pode ser útil para diagnóstico, mas nunca deve ser tratada como execução restaurável. Os únicos resultados finais aceitáveis são `SUCCESS` e `FAILED`.

Na implementação futura será avaliado o uso de `set -Eeuo pipefail`, com tratamento explícito para preservar o estado e reiniciar componentes que tenham sido parados de forma controlada. Nenhum código é criado agora.

### Cleanup obrigatório após parada controlada

Redis e Portainer deverão ser reiniciados obrigatoriamente quando tiverem sido parados para cópia consistente, inclusive se uma etapa posterior falhar. O requisito de fluxo é:

```text
stop -> tentativa de backup -> falha no tar -> cleanup/restart obrigatório -> FAILED -> exit code diferente de zero
```

O reinício não transforma uma execução falha em válida: ele apenas restaura a disponibilidade do componente antes da saída com falha. A implementação provavelmente precisará de `trap` e de uma rotina de cleanup para garantir esse comportamento, mas nenhum código é implementado neste documento.

### Logs

Os logs deverão ficar fora do repositório, no caminho proposto `/srv/teste-deploy-data/backup-logs/`. Cada execução deverá registrar, no mínimo:

- início e identificador da execução;
- componentes solicitados e ordem usada;
- sucesso ou falha de cada componente;
- criação e verificação dos checksums;
- transferência externa e sua validação;
- resultado final, término e duração.

Logs não podem registrar passwords, conteúdo de `.env`, chaves privadas, setup tokens ou outros secrets.

## Secrets e transferência externa

Os scripts futuros não podem ter passwords hardcoded. A estratégia para fornecer secrets de MySQL, MongoDB e demais recursos ainda precisa ser definida antes da implementação definitiva; ela deverá evitar valores no histórico do shell, nos argumentos expostos e nos logs.

Como decisão concreta da primeira implementação incremental, o backup MySQL usa `MYSQL_BACKUP_DEFAULTS_FILE`: uma variável de ambiente que aponta para um arquivo de opções MySQL protegido, externo ao repositório. O script não lê `.env`, não cria esse arquivo e valida que ele pertence ao usuário executor e não é legível por grupo ou outros. Essa é uma solução provisória apenas para o fluxo MySQL local; ela não define ainda a estratégia geral de gestão de secrets.

O transporte inicial proposto permanece SSH/SCP, porque já foi validado para o laboratório com a chave dedicada `~/.ssh/id_ed25519_backup_lab`. A chave não deve ser copiada para o repositório, staging, destino de backup ou documentação além do seu caminho e finalidade. Host, usuário, diretório remoto e caminho da chave deverão ser parametrizáveis, pois o endereço atual do destino pode mudar.

## Consistência por componente

| Componente | Procedimento proposto | Consideração de consistência |
|---|---|---|
| MySQL | `mysqldump` com `--single-transaction`, `--routines`, `--triggers`, `--events` e `--no-tablespaces` | Método lógico manual validado; `--no-tablespaces` foi necessário devido à ausência do privilégio `PROCESS` da conta da aplicação. |
| MongoDB | `mongodump` em archive, com autenticação sem password hardcoded | O archive lógico manual foi validado; o tratamento temporário e seguro da senha ainda precisa virar uma decisão de automação. |
| Laravel storage | Archive de `storage/app/private` | No laboratório não foi necessário parar a aplicação. Em produção, a consistência deve ser avaliada segundo o tipo, volume e mutabilidade dos arquivos. |
| Redis | `SAVE`, parada controlada, cópia do volume, reinício obrigatório por cleanup | O volume com AOF foi restaurado com sucesso. A falha durante o archive não pode impedir o reinício. Redis é tratado como estado persistente apenas neste laboratório; em produção seu papel decidirá se o backup é necessário. |
| Portainer | Parada controlada, cópia de `portainer_data`, reinício obrigatório por cleanup | O restore funcional do estado configurado foi validado. A falha durante o archive não pode impedir o reinício. |

## Ordem futura de backup

A ordem inicial proposta é:

1. MySQL;
2. MongoDB;
3. Laravel storage privado;
4. Redis;
5. Portainer.

MySQL, MongoDB e storage são copiados primeiro porque seus métodos manuais validados não exigem parada controlada no laboratório. Redis e Portainer ficam por último, pois ambos exigem uma janela curta de parada para cópia consistente do volume. Essa ordem limita a indisponibilidade dos componentes que precisam ser interrompidos e exige que cada um seja reiniciado antes de avançar.

Ela é uma proposta de laboratório, não uma garantia de consistência transacional entre serviços. A necessidade de um ponto de consistência global deverá ser reavaliada se os componentes passarem a ter dependências de negócio entre si.

## Concorrência e retenção

A automação deverá impedir duas execuções simultâneas. O mecanismo `flock` será avaliado para um lock único da execução completa; ele não é implementado neste momento.

A política provisória é manter 7 backups diários completos. A retenção futura deverá:

- ser executada somente depois que uma nova execução tiver sido transferida e verificada com sucesso;
- operar somente sobre diretórios completos, promovidos e válidos no destino externo;
- nunca considerar `.incomplete/` como conjunto de backups válidos ou candidato de retenção;
- nunca apagar indiscriminadamente artefatos individuais;
- preservar evidências de uma execução com falha até investigação ou política explícita de descarte.

## Relação com restore

Este documento define apenas a futura automação de backup. O restore automatizado terá responsabilidade, validações, permissões e riscos próprios e não deve ser criado como consequência automática destes scripts.

Os procedimentos manuais validados permanecem a referência para MySQL, MongoDB, Redis, Laravel storage e `portainer_data`. Um runbook detalhado e o teste em máquina limpa continuam necessários antes de declarar o disaster recovery concluído.

## Questões pendentes antes da implementação

- Definir a fonte e o manuseio seguro dos secrets usados pelos comandos automatizados.
- Definir formato final de logs, nível de detalhamento, rotação e monitoramento/alertas.
- Definir parâmetros configuráveis para destino SSH, diretório remoto, chave e componentes selecionados.
- Implementar e testar lock, tratamento de falhas e reinício garantido de Redis e Portainer.
- Implementar nomenclatura, manifest, verificação local/remota e retenção por execução completa.
- Definir o agendamento Cron somente depois da validação dos scripts.
- Definir o escopo de uploads públicos e de outros dados persistentes da aplicação.
- Fixar versão ou digest do Portainer antes de depender de uma reconstrução reproduzível.
- Criar runbook de restore detalhado e validar todo o fluxo em máquina limpa.

## Situação atual

O desenho da automação está definido para o laboratório. O backup local de MySQL já foi implementado e validado em cenário de sucesso e em falha proposital, incluindo dump, checksum, log e cleanup de artefatos parciais. Não há ainda transferência externa automatizada, `.incomplete` remoto, `manifest.sha256` global, orquestrador, retenção, lock global, Cron de backup, monitoramento, scripts dos demais componentes ou restore automatizado. O disaster recovery geral permanece pendente.
