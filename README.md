# CEUB · Laboratório de Entrega Contínua com .NET 10

API mínima em C# (.NET 10) entregue por dois workflows do GitHub Actions:

- **CI e Staging** (`.github/workflows/ci-staging.yml`): em cada push na `main`, restaura, compila, testa, publica, constrói **uma** imagem Docker e a guarda como artefato (`release-<SHA>`: TAR, manifest, `image-id.txt`, `SHA256SUMS`). Um runner self-hosted (label `ceub-cd`) baixa esse pacote, confere os checksums e implanta em staging (`127.0.0.1:8081`).
- **Promover para Producao** (`.github/workflows/promover-producao.yml`): execução manual que recebe o run ID de um CI aprovado, valida a origem pela API do GitHub e implanta **o mesmo pacote** em produção didática (`127.0.0.1:8082`), sem reconstruir.

## Como reproduzir

```bash
dotnet test Ceub.Delivery.slnx -c Release          # 2 testes
bash scripts/deploy.sh staging ceub-api:local false false   # ensaio local (após docker build, etapa 12)
```

1. Registre um runner self-hosted Linux x64 com a label `ceub-cd` e mantenha `./run.sh` ativo.
2. Faça push na `main` e espere **CI e Staging** ficar verde.
3. Em *Actions → Promover para Producao → Run workflow*, informe o run ID dessa execução.

## Evidências

Repositório: https://github.com/renzovaz/ceub-cd-dotnet10

### 1. CI e Staging saudável

| Item | Valor |
|---|---|
| Execução | [#1 · run 43965747320](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43965747320) |
| Commit | `3135b472bb62a91b1e04c3341849567761cdd5bb` |
| Artefato | `release-3135b472bb62a91b1e04c3341849567761cdd5bb` |
| Resposta de `/` em 8081 | `{"versao":"1.0.1","commit":"3135b47…","ambiente":"Staging"}` |

### 2. Promoção saudável: build once, deploy many

Promoção: [run 43966054929](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43966054929), com `run_id=43965747320`.

| Evidência | Staging | Produção |
|---|---|---|
| run ID de origem | 43965747320 | 43965747320 (informado na promoção) |
| Nome da imagem | `ceub-api:3135b472…cdd5bb` | `ceub-api:3135b472…cdd5bb` |
| ID da imagem | `sha256:7519315c4d915f247c7d25ca311b641d37c006295db051d263f9d97714062f32` | `sha256:7519315c4d915f247c7d25ca311b641d37c006295db051d263f9d97714062f32` |
| Ambiente HTTP | Staging | Production |
| Versão HTTP | 1.0.1 | 1.0.1 |

O log do job `production` mostra `sha256sum -c` com os 5 arquivos `OK`, `Loaded image: ceub-api:3135b47…` e `Deploy validado: production`. Não há nenhum `dotnet publish` nem `docker build`.

### 3. Experimento A: teste unitário bloqueia o deploy

- Mudança: o segundo item de `Catalogo.Listar()` passou a ter `Id = 1` (commit `aa31f6d`).
- Local: `Listar_DeveRetornarEntregasComIdentificadoresUnicos` falhou (1 falha, 1 aprovado).
- Actions: [run 43966274643](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43966274643). No job `build`, o passo **Test** falhou (`Listar_DeveRetornarEntregasComIdentificadoresUnicos`: `Assert.Equal() Failure: Expected: 2, Actual: 1`) e Publish/Empacotar foram ignorados. O job **staging foi ignorado**.
- Depois: 8081 e 8082 continuaram no commit `3135b47…`. Nenhum container foi trocado, então não houve rollback.
- Correção: `Id = 2` restaurado (commit `6ec6d91`). [Run 43966398877](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43966398877) verde, versão 1.0.3.

### 4. Experimento B: falha após iniciar a API e rollback

- Antes: produção em `/health` = 200, versão 1.0.1, commit `3135b47…`.
- Promoção: [run 43966640140](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43966640140), `run_id=43966398877`, `falha_controlada=true`. O job `production` terminou com **failure**.
- Log: o novo container iniciou (`Now listening on: http://[::]:8080`), das 20 consultas a `/health`, a primeira foi recusada enquanto a API ainda iniciava e as outras 19 responderam `503`. O script então removeu o container novo, restaurou o anterior e registrou `ROLLBACK OK: container anterior restaurado.`
- Depois: `/health` = 200, versão **1.0.1**, commit `3135b47…`, container `ceub-api-production` com a imagem anterior.

**Análise**

- O processo iniciou? Sim. O Kestrel subiu na porta 8080, mas `/health` respondeu HTTP 503.
- Causa: a configuração `FAIL_HEALTH=true`, injetada no `docker run`. O código do endpoint não mudou: a mesma imagem que passou em staging (`sha256:6b81ea68…`) falhou só por causa da configuração.
- Versões: antes da falha, 1.0.1 (`3135b47`). Depois do rollback, a mesma 1.0.1.
- O container anterior manteve a configuração saudável? Sim. Ele foi apenas parado e renomeado para `-previous`, e depois renomeado de volta e reiniciado com as variáveis originais.
- Por que o pipeline ficou vermelho? O `deploy.sh` retorna 1 depois de qualquer falha. Recuperar o serviço não torna o deploy um sucesso: a versão pedida não foi implantada, e o histórico precisa registrar isso.

**Recuperação**: [run 43966949095](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43966949095), com o mesmo `run_id` e `falha_controlada=false`, ficou verde. Produção passou a responder versão 1.0.3, commit `6ec6d91…`. Não foi preciso reconstruir nada.

### 5. Experimento C: feature flag

Mesmo pacote (`run_id=43966398877`), mesma imagem `sha256:6b81ea686f249e6758fcc2b2b20bb293f1892c5fa6de14384c21c2243d731059` nas três situações:

| Promoção | `novidade` | `GET /api/novidade` |
|---|---|---|
| [43966949095](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43966949095) | false | 404 |
| [43967129640](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43967129640) | true | 200 `{"mensagem":"Nova consulta de entregas liberada!"}` |
| [43967303526](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43967303526) | false | 404 |

Cada mudança da flag recriou o container, com uma breve interrupção. Mudar a flag sem novo deploy exigiria configuração dinâmica.

## Gate manual, estratégia e limites

- **Gate manual**: produção só recebe uma versão quando alguém dispara *Promover para Producao* com o run ID de um *CI e Staging* bem-sucedido na `main`. O job `validar-origem` confere isso pela API. Isso é **Continuous Delivery**: cada candidato aprovado está pronto, mas a decisão de implantar é humana e fica registrada. Os environments `staging` e `production` existem, mas sem regras de proteção (nenhum *required reviewer*). Os planos Free, Pro e Team restringem esse recurso em repositórios privados, e o repositório continua privado. Por isso o gate é uma decisão registrada de quem dispara o workflow, não uma revisão independente por outra pessoa.
- **Estratégia**: o `deploy.sh` implementa **recreate**. Ele para o container ativo, renomeia para `-previous` e inicia o novo na mesma porta. Há uma janela de indisponibilidade, e as duas versões nunca atendem ao mesmo tempo, então não é blue-green. O predecessor parado serve só para rollback. A feature flag foi usada junto, como controle de exposição.
- **Limites do ambiente local**: staging e produção compartilham o mesmo PC, o mesmo Docker e o mesmo runner, sem isolamento nem alta disponibilidade. As APIs só respondem em `127.0.0.1`. O rollback guarda um único predecessor e não trata dados. O artefato expira em 7 dias. Não há registry, TLS, métricas, tracing nem alertas. Logs ficam no `docker logs` e no Actions. Uma produção real acrescentaria registry com digest, identidade, ambientes isolados e observabilidade centralizada.

## Estado ao final do laboratório

| Ambiente | Versão | Commit | ID da imagem | Origem |
|---|---|---|---|---|
| Staging (8081) | 1.0.4 | `a697dc8…` | `sha256:d606f40e…` | [CI #4 · run 43967593760](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43967593760), disparado pelo commit do README |
| Produção (8082) | 1.0.3 | `6ec6d91…` | `sha256:6b81ea68…` | Artefato do [CI #3 · run 43966398877](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43966398877), promovido em [43967303526](https://github.com/renzovaz/ceub-cd-dotnet10/actions/runs/43967303526) |

**Qual versão está atendendo agora, qual artefato a gerou e como recuperar a anterior?** Produção atende a versão 1.0.3 (commit `6ec6d91`), gerada pelo artefato `release-6ec6d9193dc263dd9bad084d6fa47a18cf1bb131` do run 43966398877. Para voltar à versão anterior do código (1.0.1), basta promover de novo o run aprovado 43965747320 enquanto o artefato não expira. Não é preciso reconstruir nada. O container `ceub-api-production-previous` guarda só a implantação imediatamente anterior: a mesma imagem 1.0.3, mas com `FEATURE_NOVIDADE=true`. Ele serve para o rollback automático do script, não para voltar à 1.0.1.

## Checklist (etapa 42)

- [x] A API compila para net10.0 e os testes passam.
- [x] Staging e produção respondem nas portas 8081 e 8082.
- [x] A promoção usa o run ID de um CI aprovado.
- [x] Os IDs das imagens promovidas são iguais (`sha256:7519315c…` em staging e produção).
- [x] Uma falha de teste impede a implantação em staging (run 43966274643).
- [x] Uma falha HTTP após o deploy restaura a versão anterior (run 43966640140).
- [x] O workflow da implantação defeituosa permanece vermelho.
- [x] Extensão C: a feature flag altera a resposta sem mudar a imagem.
- [x] O README liga cada evidência ao commit e à execução.

Arquivos brutos (saídas de curl/docker e logs dos jobs) estão em [`evidencias/`](evidencias/).
