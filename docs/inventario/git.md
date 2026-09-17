# Git e versionamento — TESTE-DEPLOY

## Estado originalmente encontrado

- Projeto inspecionado: `/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy`
- Caminho `.git`: existe como diretório.
- Conteúdo de `.git`: vazio; não contém `HEAD`, `config`, `objects` nem `refs`.
- Repositório funcional: não identificado.

Os comandos `git rev-parse --show-toplevel`, `git status`, `git branch --show-current` e `git remote -v` retornaram o mesmo erro: o diretório atual, nem seus pais até o ponto de montagem, é um repositório Git.

Por não existir repositório válido naquele momento, não havia branch atual, remote configurado, arquivos rastreados, modificações Git ou arquivos não rastreados que pudessem ser determinados pelo Git.

Este é um registro histórico do primeiro inventário. Ele não descreve o estado atual após a preparação do laboratório.

## Estado atual após a preparação do laboratório

| Item | Estado confirmado |
|---|---|
| Repositório local | Funcional |
| Branch principal | `main` |
| Commit inicial | `77bdce8 Initial commit` |
| Arquivos no commit inicial | 126 |
| Remote | `origin` → `https://github.com/brayanfv/laravel-disaster-recovery-lab.git` |
| Rastreamento | `main` rastreia `origin/main` |
| Publicação inicial | Primeiro push concluído |
| Working tree | Limpo (`git status`) |
| Plataforma remota do laboratório | GitHub |

O gap de Git/versionamento está resolvido para este laboratório. No ambiente real, o versionamento deverá utilizar Git/Bonobo conforme a infraestrutura e as políticas da empresa; esse cenário corporativo não foi validado neste laboratório.

## Diretório pai

O diretório `/home/lucas-cooperja/Documentos/laravel-deploy-test` não contém `.git`. Seus únicos itens relevantes são:

- `teste-deploy/`, o projeto Laravel atual;
- `.env.example`, um arquivo isolado sem outros marcadores de aplicação ou repositório nesse nível.

Não há evidência suficiente para determinar se o projeto foi copiado de outro repositório, se o `.git` vazio foi deixado por uma cópia incompleta ou se foi criado por outro mecanismo. Nenhuma tentativa de reparo foi feita.

## Arquivos excluídos e validação

O `.gitignore` raiz e os arquivos internos de ignore cobrem os itens relevantes abaixo.

| Item | Estado de exclusão identificado | Observação |
|---|---|---|
| `.env`, `.env.backup`, `.env.production` | Ignorado; não versionado | Arquivos de configuração com secrets. |
| `vendor/` | Ignorado; não versionado | Dependência PHP reconstruível. |
| `node_modules/` | Ignorado; não versionado | Dependência JavaScript reconstruível. |
| `*.log` e `storage/logs/*` | Ignorados; logs reais não versionados | Logs de aplicação não devem ser versionados. |
| `storage/framework/cache`, `sessions`, `testing`, `views` | Ignorados por `.gitignore` internos | Caches, sessões em filesystem e views compiladas. |
| `storage/app/private` e `storage/app/public` | Conteúdo ignorado por `.gitignore` internos | Dados persistentes potenciais não devem ser versionados. |
| `bootstrap/cache/*` | Ignorado por `bootstrap/cache/.gitignore` | Artefatos gerados pelo framework/Composer. |
| `public/build`, `public/hot`, `public/storage` | Ignorados no `.gitignore` raiz | Artefatos de build e link de storage. |
| `.codex/` | Ignorado no `.gitignore` raiz | Dados locais da ferramenta não devem ser versionados. |
| `/storage/*.key`, `/auth.json` | Ignorados; não versionados | Material sensível/configuração de autenticação. |

## Arquivos potencialmente sensíveis identificados

No inventário inicial, fora de `vendor/` e `node_modules`, foram identificados somente:

- `.env`
- `.env.example`

Na preparação para o commit inicial, `.env.example` foi validado como modelo sem valores sensíveis reais. Não foram identificados arquivos de chave privada, credenciais ou secrets no commit inicial; `docs/inventario/secrets.md` registra somente caminhos e nomes de variáveis, sem valores.

## Classificação preliminar

| Item | Tipo | Tratamento esperado em versionamento futuro |
|---|---|---|
| `app`, `routes`, `resources`, `tests`, `database` | Código versionável | Versionar. |
| `config`, `composer.json`, `composer.lock`, `package.json`, `package-lock.json`, `vite.config.js`, `tailwind.config.js` | Configuração e definição versionável | Versionar, exceto valores secretos externos. |
| `docs/` | Documentação versionável | Versionar. |
| `.editorconfig`, `.gitattributes`, `.gitignore` | Configuração de repositório versionável | Versionar. |
| `.env` | Configuração com secrets | Não versionar. |
| `.env.example` | Modelo de configuração sem valores reais | Versionado no commit inicial após validação. |
| `vendor/`, `node_modules/`, `public/build`, `bootstrap/cache`, `storage/framework` | Dependências e artefatos reconstruíveis | Não versionar. |
| `storage/app/private`, `storage/app/public` | Dados persistentes potenciais | Não versionar; tratar fora do fluxo de Git. |
| MySQL, sessões, cache, filas e logs | Dados operacionais/persistentes | Não pertencem ao Git. |

## Escopo e limites do Git

Git protege código, documentação e configuração versionável. Ele não substitui backup ou recuperação de:

- bancos de dados;
- `.env` e outros secrets;
- uploads e demais arquivos persistentes;
- volumes persistentes, incluindo `portainer_data`;
- dados de aplicação e estado operacional.

## Pendências

- Validar futuramente o fluxo Git/Bonobo exigido pela infraestrutura corporativa.
- Definir, separadamente, backup e recuperação para bancos, secrets, uploads, volumes e dados persistentes.

## Situação atual

Este documento preserva o estado originalmente encontrado e registra o estado atual confirmado após a preparação do laboratório. O repositório local e o remoto GitHub já existem; esta atualização documental não executou comandos Git de escrita, commit ou push.
