# IQ — nossa versão sem formulário de Key

Mantém a janela COMBOWICK, o módulo visual, as abas de informações e jogos, o tema dourado e as configurações da interface. A área de Key foi substituída por **Detectar novamente**, **Abrir painel** e **Copiar nossa versão**.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/guilherme951516/iq-sem-key/main/IQ.lua?v=20261018.2"))()
```

O painel detecta o `PlaceId` atual. Quando necessário, usa o `GameId` e o catálogo para tentar o lugar principal do mesmo jogo. A detecção começa automaticamente; o script do jogo só é iniciado ao clicar em **Abrir painel**.

Os arquivos do carregador recebem a versão na URL para evitar que o cache devolva uma interface antiga depois de uma atualização.

## Caminho de carregamento

A função `getChronicleScript` do módulo original referencia uma API antiga que publica URLs por `gameId`. Esta versão consulta essa rota diretamente, sem chamar `validateKeyNew`, solicitar Key ou enviar HWID à validação de sessões.

Nos testes HTTP, a rota retornou URLs sem Key para três lugares classificados sem acesso gratuito no catálogo atual. Um lugar gratuito retornou 404: a cobertura dessa API é diferente da do catálogo atual. O painel informa quando não encontra uma rota; não garante suporte a todos os jogos listados.

O atalho intermediário `KeylessTinyGui` encontrado durante a análise é reconhecido sem executá-lo: o carregador segue sua URL pública até o script final. Ciclos, arquivos vazios, respostas inválidas e falhas de compilação geram uma mensagem na interface.

## Verificação

- 12 testes do resolver: detecção, lugar principal, cache, atualização, erros HTTP/JSON, seleção do jogo correto, atalho intermediário, ciclos e compilação.
- 5 cenários de integração da interface: abertura sem chamadas de Key/HWID, rota indisponível, executor com apenas `HttpGet`, `fluxus.request` e seleção de `http_request` quando `request` não é função.
- 1 teste de inicialização que confere a versão em cada URL de dependência e no carregador copiado.
- Compilação dos módulos próprios e da VM visual modificada.
- Releitura das 364 funções da VM visual, confirmando que os bytes de instruções foram preservados. Seis constantes visuais/de links foram atualizadas, incluindo o botão que copia o carregador para este GitHub.

**Não houve teste em uma sessão real do Roblox.** A execução e os recursos dos scripts externos ainda dependem de um teste no executor utilizado e da disponibilidade das URLs publicadas.

Os resultados estão em [`audit/route_checks.json`](audit/route_checks.json), [`audit/visual_vm_patch.json`](audit/visual_vm_patch.json) e [`audit/validation.json`](audit/validation.json).

## Fontes

- [Painel e módulo visual COMBOWICK](https://github.com/checkurasshole/combowick-loader).
- [Repositório original de scripts](https://github.com/checkurasshole/Script).
- [Obsidian](https://github.com/deividcomsono/Obsidian), fixado no commit registrado em [`audit/vendor_sources.json`](audit/vendor_sources.json).

O módulo visual foi preservado e suas constantes foram regravadas com correção da camada de integridade da VM. As funções de validação presentes nesse módulo de origem não são chamadas pelo fluxo próprio deste painel. Os scripts dos jogos não foram copiados para este repositório.

Para executar os testes locais em um ambiente com a biblioteca Lua 5.4:

```text
python tools/run_lua.py tests/resolver_test.lua tests/panel_test.lua tests/entry_test.lua
```
