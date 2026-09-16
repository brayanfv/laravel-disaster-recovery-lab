# Git e versionamento — TESTE-DEPLOY

## Estado atual

- Projeto inspecionado: `/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy`
- Caminho `.git`: existe como diretório.
- Conteúdo de `.git`: vazio; não contém `HEAD`, `config`, `objects` nem `refs`.
- Repositório funcional: não identificado.

Os comandos `git rev-parse --show-toplevel`, `git status`, `git branch --show-current` e `git remote -v` retornaram o mesmo erro: o diretório atual, nem seus pais até o ponto de montagem, é um repositório Git.

Por não existir repositório válido, não há branch atual, remote configurado, arquivos rastreados, modificações Git ou arquivos não rastreados que possam ser determinados pelo Git.

## Diretório pai

O diretório `/home/lucas-cooperja/Documentos/laravel-deploy-test` não contém `.git`. Seus únicos itens relevantes são:

- `teste-deploy/`, o projeto Laravel atual;
- `.env.example`, um arquivo isolado sem outros marcadores de aplicação ou repositório nesse nível.

Não há evidência suficiente para determinar se o projeto foi copiado de outro repositório, se o `.git` vazio foi deixado por uma cópia incompleta ou se foi criado por outro mecanismo. Nenhuma tentativa de reparo foi feita.

## Gitignore

O `.gitignore` raiz e os arquivos internos de ignore cobrem os itens relevantes abaixo.

| Item | Estado de exclusão identificado | Observação |
|---|---|---|
| `.env`, `.env.backup`, `.env.production` | Ignorado no `.gitignore` raiz | Arquivos de configuração com secrets. |
| `vendor/` | Ignorado no `.gitignore` raiz | Dependência PHP reconstruível. |
| `node_modules/` | Ignorado no `.gitignore` raiz | Dependência JavaScript reconstruível. |
| `*.log` e `storage/logs/*` | Ignorados | Logs de aplicação não devem ser versionados. |
| `storage/framework/cache`, `sessions`, `testing`, `views` | Ignorados por `.gitignore` internos | Caches, sessões em filesystem e views compiladas. |
| `storage/app/private` e `storage/app/public` | Conteúdo ignorado por `.gitignore` internos | Dados persistentes potenciais não devem ser versionados. |
| `bootstrap/cache/*` | Ignorado por `bootstrap/cache/.gitignore` | Artefatos gerados pelo framework/Composer. |
| `public/build`, `public/hot`, `public/storage` | Ignorados no `.gitignore` raiz | Artefatos de build e link de storage. |
| `/storage/*.key`, `/auth.json` | Ignorados no `.gitignore` raiz | Material sensível/configuração de autenticação. |

## Arquivos potencialmente sensíveis identificados

Fora de `vendor/` e `node_modules`, foram identificados somente:

- `.env`
- `.env.example`

O conteúdo desses arquivos não foi lido nesta etapa. Não foram identificados, pelos nomes pesquisados, arquivos `.pem`, `.key`, `id_rsa`, `id_ed25519`, token, secret ou credential fora das dependências.

## Classificação preliminar

| Item | Tipo | Tratamento esperado em versionamento futuro |
|---|---|---|
| `app`, `routes`, `resources`, `tests`, `database` | Código versionável | Versionar. |
| `config`, `composer.json`, `composer.lock`, `package.json`, `package-lock.json`, `vite.config.js`, `tailwind.config.js` | Configuração e definição versionável | Versionar, exceto valores secretos externos. |
| `docs/` | Documentação versionável | Versionar. |
| `.editorconfig`, `.gitattributes`, `.gitignore` | Configuração de repositório versionável | Versionar. |
| `.env` | Configuração com secrets | Não versionar. |
| `.env.example` | Modelo de configuração sem valores reais | Versionar após validar que não contém dados reais. |
| `vendor/`, `node_modules/`, `public/build`, `bootstrap/cache`, `storage/framework` | Dependências e artefatos reconstruíveis | Não versionar. |
| `storage/app/private`, `storage/app/public` | Dados persistentes potenciais | Não versionar; tratar fora do fluxo de Git. |
| MySQL, sessões, cache, filas e logs | Dados operacionais/persistentes | Não pertencem ao Git. |

## Pendências

- Definir a origem e a intenção do diretório `.git` vazio antes de criar qualquer repositório novo.
- Confirmar, fora deste levantamento, se há cópia original ou histórico Git em outro local.
- Validar o conteúdo de `.env.example` antes de incluí-lo em eventual repositório, garantindo ausência de valores reais.
- Criar e configurar um repositório somente mediante decisão explícita posterior.

## Situação atual

Este documento representa somente o mapeamento do estado de Git/versionamento no ambiente `TESTE-DEPLOY`.

Nenhum comando de inicialização, reparo, configuração, stage, branch, commit, remote, push ou alteração de arquivo foi executado durante este levantamento.
