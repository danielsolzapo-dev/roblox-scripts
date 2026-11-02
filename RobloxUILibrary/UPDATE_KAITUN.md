# Kaitun coordenado

A aba **Kaitun** usa o Level Farm e os objetivos First Sea já presentes no
Standalone. Escolha o nível alvo, os objetivos opcionais Saber e Segundo Sea e
ative **Iniciar Kaitun**. Cada execução começa manualmente; carregar preferências
não inicia a fila.

- Saber estabelece nível alvo mínimo 200; Segundo Sea, 700.
- Um único worker de movimento fica sob controle da fila por vez.
- Outro farm/movimento manual, edição das opções, Parar ou unload interrompe a fila.
- Posse desconhecida do Saber aguarda inventário; não presume item ausente.
- Sem progresso observado por 180 segundos, pausa e registra o motivo. O tempo é ajustável.
- Ao morrer, libera o worker e aguarda respawn, respeitando o limite sem progresso.
- Restaura modo e autoequip passivos ao parar, sem reativar farms anteriores.
- Estado disponível no diagnóstico em `Features.Kaitun`.

Esta atualização não implementa desbloqueio do Terceiro Sea, Godhuman, CDK ou
compra automática de frutas/estilos pela fila. Objetivos do First Sea são
ignorados quando a conta já está em outro Sea. Após teleporte, execute o hub e
inicie a fila novamente. Não há retomada automática no teleporte.

Implementação própria, sem incorporar código de terceiros sem licença nem
carregar hubs remotos. A pesquisa serviu para orientar separação de política,
ciclo de vida, posse de workers e apresentação de progresso.

## Verificação

`python3 tests/run_kaitun.py /caminho/para/luau` executa a política e o ciclo de
vida com mocks. `python3 scripts/sync_kaitun.py --check` confere a política
embutida. A edição deve ser feita em `KaitunPlanner.luau`, seguida de
`python3 scripts/sync_kaitun.py`.

Os testes locais não validam coordenadas, contratos remotos, dano ou recompensas
no Blox Fruits; esses pontos precisam de teste dentro do jogo.
