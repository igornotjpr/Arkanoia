# Changelog

Versionamento semântico: `MAJOR.MINOR.PATCH`. Neste projeto, **MAJOR** muda
quando o jogo ganha um marco de conteúdo (power-ups, novas fases), **MINOR**
quando entra comportamento novo dentro do marco atual, e **PATCH** quando é só
correção.

Cada versão é uma tag anotada em `main`. Para ver o que uma tag carrega:

```bash
git show v1.1.0            # a anotação e o commit
git log v1.0.0..v1.1.0     # tudo que entrou entre as duas
```

---

## v1.1.0 — 30/07/2026

### Corrigido

- **Ranking global não carregava no navegador**, exibindo `FALHA DE REDE (8)`. O
  código 8 é `RESULT_BODY_DECOMPRESS_FAILED`, e não `RESULT_REQUEST_FAILED`
  (que vale 9), então caía no texto de erro genérico. A Cloudflare do Supabase
  responde com `Content-Encoding: gzip`; na web o `fetch()` do navegador já
  entrega o corpo descomprimido mas mantém o cabeçalho, e o Godot tentava
  descomprimir JSON puro. `accept_gzip` agora fica desligado apenas na web.
- **Build web engordava a cada exportação** (91 KB → 117 KB no `.pck`). O Godot
  importava os PNGs que ele mesmo tinha acabado de exportar em `docs/`, e eles
  voltavam para dentro do pacote seguinte. Resolvido com `docs/.gdignore`.

### Alterado

- **Pause virou menu**, com os botões `CONTINUAR` e `SAIR PARA O INÍCIO` em cinza
  sobre branco, preservando o disfarce de escritório. Clique fora dos botões não
  faz mais nada — antes, clique em qualquer lugar despausava, e com um menu na
  tela sair por engano custaria a corrida inteira. `P` e `Esc` seguem sendo o
  despause de uma tecla. Sair pelo menu abandona a partida sem enviar pontuação.
- **A raquete não volta mais ao centro** a cada vida perdida e a cada fase nova.
  No mouse isso era invisível, porque o cursor reassumia a posição no quadro
  seguinte; no teclado ela teleportava para o meio da tela. A posição central
  agora só vale no começo de uma partida.

---

## v1.0.0 — 30/07/2026

Primeira versão jogável: uma fase, gráficos e efeitos completos, lógica coberta
por testes headless. Leaderboard global no Supabase, controles de mouse, teclado
e toque, pause discreto e publicação no GitHub Pages.

Tiros, power-ups e aceleração temporária ficam para etapas seguintes.
