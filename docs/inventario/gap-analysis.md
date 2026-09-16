# Gap Analysis — TESTE-DEPLOY

## Objetivo e escopo

Esta análise compara exclusivamente o inventário validado do ambiente `TESTE-DEPLOY` com o cenário-alvo de laboratório para testes futuros de backup e disaster recovery. Não define uma estratégia final de backup ou restore, nem autoriza mudanças no ambiente.

## Estado geral

O ambiente possui a base Laravel/PHP, MySQL, Docker, Nginx, UFW, Fail2Ban, Cron e Portainer. Contudo, ainda não tem os componentes e dados necessários para exercitar uma recuperação completa e representativa: MongoDB e Redis estão ausentes; Git não é funcional; não há dados persistentes de uploads; Scheduler e filas não têm trabalho real; HTTPS não está configurado; e não há local de armazenamento de backups definido.

A raiz continua com aproximadamente 15,8 GB e foi identificada anteriormente como um limite crítico. Para disponibilizar capacidade ao laboratório, foi criada uma partição ext4 persistente de aproximadamente 30 GB em `/srv/teste-deploy-data`, com cerca de 28 GB livres. Isso resolve a lacuna de capacidade planejada para dados do laboratório, mas não amplia a raiz nem cria armazenamento externo para backups.

## Matriz de gaps

| Componente | Estado atual | Estado desejado | Gap | Ação futura sugerida | Prioridade |
|---|---|---|---|---|---|
| Host/Sistema Operacional | Linux Mint 22.3, base Ubuntu; raiz com ~15,8 GB; partição local adicional com ~28 GB livres em `/srv/teste-deploy-data` | Linux equivalente com capacidade suficiente para o laboratório | Capacidade local planejada resolvida; a raiz não foi ampliada e serviços em caminhos padrão ainda podem depender dela | Decidir futuramente quais dados e serviços usarão a nova partição, sem alterar a montagem atual | Resolvida para capacidade do laboratório |
| Laravel/PHP | Laravel 13.27.0, PHP 8.3.6; ambiente `local` e debug habilitado | Aplicação funcional com configuração de laboratório explícita | Ambiente e debug não foram validados como representação do cenário-alvo | Definir futuramente os parâmetros de laboratório a reproduzir | Média |
| Git/versionamento | `.git` é diretório vazio; não há repositório, branch ou remote | Repositório funcional com código e documentação versionáveis | Código não possui histórico nem origem verificável | Decidir a origem do código e criar/versionar somente após validação | Alta |
| Docker e Docker Compose | Docker e Compose instalados; nenhum projeto Compose associado aos containers | Infraestrutura reproduzível por definição declarativa | Portainer foi criado fora de Compose; não há definição de infraestrutura versionável | Decidir formato de definição da infraestrutura e versões fixas | Alta |
| MySQL | MySQL ativo, banco `teste_deploy`, tabelas Laravel presentes | Banco reproduzível com dados de laboratório representativos | Dados de negócio mínimos; medição física do datadir ainda pendente | Criar futuramente dados fictícios e medir armazenamento antes do teste | Alta |
| MongoDB | Ausente | Presente caso faça parte do cenário-alvo | Componente inexistente | Decidir uso no laboratório e instalar/configurar somente em etapa posterior | Alta |
| Redis | Ausente; Laravel usa `database` para cache, sessão e fila | Presente caso o cenário-alvo exija Redis | Componente inexistente e não exercitado pela aplicação | Decidir se Redis deve ser introduzido e quais drivers Laravel usariam o serviço | Alta |
| Nginx | Nginx HTTP ativo na porta 80; rate limits customizados | Proxy web com configuração validada para o laboratório | HTTPS ausente; blocos PHP e aplicação de rate limits ainda pendentes de validação | Decidir se HTTPS integra o laboratório e validar configurações existentes | Média |
| UFW | Ativo; entrada `deny`, libera SSH e HTTP em IPv4/IPv6 | Regras de segurança reproduzíveis e coerentes com serviços | Arquivos efetivos e regra explícita de saída SSH ainda requerem revisão | Validar as regras persistidas e a necessidade da exceção de saída | Média |
| Fail2Ban | Ativo; jail `sshd`; ação `iptables-multiport` | Proteção coerente com serviços expostos | Backend efetivo e filtro Nginx customizado ainda não validados | Validar backend, ação e propósito do filtro Nginx antes de ampliar jails | Média |
| Portainer | Em execução; volume persistente; imagem `portainer/portainer-ce:latest` | Administração reprodutível com versão conhecida | Uso de tag mutável `latest`; dados persistentes ainda não classificados internamente | Fixar versão/digest por decisão futura e validar dados do volume | Alta |
| Cron | Serviço ativo; sem crontab de usuário/root; tarefas de pacote e Sendmail local | Automação de laboratório explícita e documentada | Não há job para aplicação, backup ou Scheduler | Decidir futuros jobs somente após definir os fluxos do laboratório | Média |
| Laravel Scheduler | Nenhuma tarefa e nenhum disparo `schedule:run` | Tarefas de teste quando a aplicação exigir automação | Scheduler não exercitado | Criar tarefas somente quando houver objetivo de teste definido | Média |
| Filas, cache e sessão | Todos usam MySQL; tabelas existem; jobs/cache/falhas vazios; sessões têm ~6.604 linhas estimadas | Dados operacionais representativos para teste de perda/recuperação | Fila e cache não possuem carga real; sessões são o único conjunto operacional relevante | Criar futuramente cenários fictícios de fila, cache e sessão | Alta |
| Laravel storage | `storage/app/private` e `storage/app/public` sem dados; `public/storage` ausente | Arquivos persistentes de aplicação e uploads de teste | Não há upload, documento ou arquivo público para recuperar | Criar futuramente dados fictícios e validar o fluxo público/privado | Alta |
| Dados persistentes de aplicação | MySQL contém usuários, migrations e sessões; Portainer possui volume próprio | Conjunto mínimo e seguro de dados representativos | Cobertura atual não testa recuperação de arquivos nem fluxos de negócio | Definir e gerar futuramente dados fictícios representativos | Alta |
| Secrets/configuração | `.env` existe com permissão `664`; secrets e credenciais identificados por nome | Secrets protegidos e reproduzíveis sem valores em Git | Grupo `nogroup` tem leitura; procedimentos de transporte seguro não foram definidos | Revisar necessidade das permissões e definir tratamento seguro posteriormente | Alta |
| HTTPS/TLS | Nenhum TLS ativo; apenas estrutura Certbot sem certificados emitidos | HTTPS se fizer parte do laboratório-alvo | Ausência de certificado, chave e renovação validada | Decidir se HTTPS deve compor o cenário antes de configurar | Média |
| Armazenamento de backups | Não identificado | Destino definido, dimensionado e acessível ao laboratório | Não existe local, retenção ou capacidade de armazenamento definida | Decidir futuramente o destino e os requisitos de espaço | Crítica |
| Reconstrução em segunda máquina | Não identificada | Segunda máquina ou equivalente capaz de reconstruir o ambiente | Não há destino, automação declarativa ou teste de reconstrução | Definir futuramente a máquina-alvo e o critério de sucesso do teste | Crítica |

## Classificação por natureza

| Natureza | Elementos atuais | Implicação para o laboratório |
|---|---|---|
| Código/versionamento | Código Laravel, configurações sem secrets, migrations, lockfiles e documentação existem; Git não é funcional | O código é potencialmente versionável, mas falta o mecanismo de versionamento. |
| Configuração | Nginx, UFW, Fail2Ban, Cron, MySQL, Laravel e Portainer possuem configurações identificadas | Configurações precisam ser comparadas, reproduzidas e validadas antes de uma reconstrução. |
| Infraestrutura | Host, Docker, Compose, MySQL, Nginx, UFW, Fail2Ban, Cron e Portainer estão presentes | MongoDB, Redis e uma definição declarativa/reproduzível de infraestrutura continuam ausentes. |
| Dado persistente | MySQL `teste_deploy`, volume `portainer_data`, futuros arquivos em `storage/app` | Há dados mínimos no banco e Portainer, mas faltam dados fictícios de aplicação e uploads. |
| Secret | `.env`, `APP_KEY`, credenciais de banco/serviços e `/etc/mysql/debian.cnf` | Devem permanecer fora do Git e requerem tratamento protegido para reconstrução. |
| Temporário/reconstruível | `vendor`, `node_modules`, caches, views compiladas, logs, cache/locks de banco | Não devem orientar o teste de persistência; podem ser recriados após reconstrução. |
| Componente de segurança | UFW, Fail2Ban, SSH e Nginx | Estão presentes, mas HTTPS e algumas validações de regras/filtros ainda são gaps. |
| Ferramenta operacional | Docker, Compose, Portainer, Cron e Git | Docker/Portainer/Cron existem; Git é inválido e Compose não representa a infraestrutura atual. |

## Prioridades para a próxima fase

1. **Crítica:** decidir o destino e a capacidade do armazenamento de backups, sem implementá-lo ainda.
2. **Crítica:** definir o destino e os critérios para uma futura reconstrução em segunda máquina.
3. **Alta:** estabelecer versionamento Git funcional após esclarecer a origem do diretório `.git` vazio.
4. **Alta:** decidir e introduzir posteriormente MongoDB e Redis se ambos integrarem o cenário-alvo.
5. **Alta:** decidir quais dados e serviços de laboratório usarão `/srv/teste-deploy-data`; a nova capacidade não muda automaticamente os caminhos padrão da raiz.
6. **Alta:** criar dados fictícios representativos em MySQL, `storage/app`, sessões, cache e filas para validar recuperação.
7. **Alta:** substituir a dependência de tag `latest` do Portainer por versão ou digest definido em decisão futura.
8. **Alta:** revisar a necessidade da permissão `664` nos arquivos `.env` e o tratamento seguro de secrets.
9. **Média:** decidir se HTTPS, Scheduler e jobs de Cron integram o laboratório.
10. **Média:** concluir as validações pendentes de Nginx, UFW e Fail2Ban antes de declarar a postura de segurança reproduzível.

## Itens não necessários no estado atual

- Containers `hello-world` e `ubuntu` parados não possuem mounts ou estado persistente; são recursos descartáveis de teste, sem papel identificado no cenário-alvo.
- S3 está apenas definido como possibilidade de configuração Laravel, sem evidência de uso; sua inclusão depende de decisão posterior.

## Limites desta análise

- Esta Gap Analysis não autoriza instalação, criação de dados, alteração de configuração, criação de jobs, Git, containers, bancos, backups ou restore.
- As ações futuras sugeridas são apenas direcionamentos de planejamento; não constituem estratégia final de backup ou recuperação.
- Os itens classificados como ausentes ou pendentes não estão concluídos.
