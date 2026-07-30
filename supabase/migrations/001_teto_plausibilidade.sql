-- ============================================================================
--  Arkanoia - migracao 001: teto de plausibilidade
--  Rode no SQL Editor do Supabase ANTES de publicar a v1.2.0 do jogo.
-- ============================================================================
--
--  Por que
--  -------
--  Os power-ups introduzem um multiplicador de risco: quem joga com a raquete
--  curta, a bola rapida ou o campo mentindo ganha mais por bloco. O teto antigo
--  (1200 pontos por segundo) nao chegava a apertar - uma partida real faz cerca
--  de 40 pts/s -, mas o novo maximo teorico por bloco subiu de 800 para 2000, e
--  o teto passa a ser derivado desse maximo em vez de estimado.
--
--  O numero: 2000 pontos por bloco x ~1,2 blocos por segundo sustentaveis (o
--  limite e o tempo de ida e volta da bola ate a raquete) = 2400 pts/s.
--
--  O termo aditivo absorve as somas que caem dentro de um mesmo segundo: bonus
--  de fase (5000) + vidas restantes (2500) + uma varredura de quatro capsulas
--  no risco maximo (3000) = ~10500, dobrado por seguranca.
--
--  ATENCAO: estes dois numeros sao espelhados por ScoreRules.
--  PLAUSIBLE_POINTS_PER_SECOND e PLAUSIBLE_BASE, e ha um teste na suite
--  (_test_schema_mirror) que le este arquivo e o schema.sql e falha se
--  divergirem. Mudou aqui, mude la.
-- ============================================================================

alter table public.scores drop constraint if exists scores_plausible;

alter table public.scores add constraint scores_plausible check (
	score <= 2400 * greatest(duration_ms / 1000, 1) + 20000
);


-- ---------------------------------------------------------------------------
-- Verificacao rapida (opcional, rode depois)
-- ---------------------------------------------------------------------------
-- Deve inserir com sucesso (partida boa com power-ups, 3 minutos):
--   insert into public.scores (nick, score, level, duration_ms)
--   values ('TESTE', 40000, 2, 180000);
--
-- Deve FALHAR (placar maximo forjado em 1 segundo):
--   insert into public.scores (nick, score, duration_ms)
--   values ('CHEAT', 999999, 1000);
