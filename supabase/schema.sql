-- ============================================================================
--  Arkanoia - schema do leaderboard global
--  Rode este arquivo inteiro no SQL Editor do Supabase (uma vez).
--  Projeto: aqcpaqjvsdsyxlmnbvav
-- ============================================================================
--
--  MODELO DE SEGURANCA (versao 1)
--  ------------------------------
--  O jogo e estatico e publico, portanto a chave publishable esta visivel no
--  navegador. A protecao NAO vem do sigilo da chave, e sim daqui:
--
--    * RLS permite apenas SELECT e INSERT para o papel anon. Nada de UPDATE ou
--      DELETE - nenhuma politica os autoriza.
--    * Privilegios por coluna: o cliente nao consegue escrever id, created_at
--      nem client_fingerprint, e nao consegue LER client_fingerprint.
--    * CHECK constraints barram nick fora do formato, pontuacao fora da faixa e
--      a combinacao "pontuacao altissima em partida curtissima".
--    * Um trigger limita envios por origem (5 por minuto) e devolve HTTP 429.
--
--  Isso impede vandalismo casual e placares absurdos, mas NAO impede alguem
--  determinado de montar um POST plausivel via curl. A blindagem real e a etapa
--  2 do plano (Edge Function assinando a sessao) - ver README.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. Tabela de pontuacoes
-- ---------------------------------------------------------------------------
create table if not exists public.scores (
	id                 bigint generated always as identity primary key,
	nick               text        not null,
	score              integer     not null,
	level              integer     not null default 1,
	duration_ms        integer     not null default 0,
	client_fingerprint text,
	created_at         timestamptz not null default now(),

	-- Espelha NickUtil.sanitize() no cliente: maiusculas, sem acento,
	-- 2 a 10 caracteres. Elimina qualquer risco de markup na renderizacao.
	constraint scores_nick_format check (nick ~ '^[A-Z0-9 ._-]{2,10}$'),

	-- Espelha ScoreRules.MAX_VALID_SCORE.
	constraint scores_score_range check (score between 0 and 999999),
	constraint scores_level_range check (level between 1 and 9999),
	constraint scores_duration_range check (duration_ms between 0 and 86400000),

	-- Plausibilidade grosseira: 1200 pontos por segundo de partida, mais uma
	-- folga inicial. Uma partida excelente fica MUITO abaixo desse teto; um
	-- placar maximo forjado precisaria alegar ~14 minutos de jogo.
	constraint scores_plausible check (
		score <= 1200 * greatest(duration_ms / 1000, 1) + 5000
	)
);

comment on table public.scores is
	'Envios de pontuacao do Arkanoia. Insercao anonima, leitura via view leaderboard.';
comment on column public.scores.client_fingerprint is
	'md5(ip + salt). Usado apenas para rate limit; nao e legivel pelo papel anon.';


-- ---------------------------------------------------------------------------
-- 2. Indices
-- ---------------------------------------------------------------------------
create index if not exists scores_leaderboard_idx
	on public.scores (score desc, created_at asc);

create index if not exists scores_nick_best_idx
	on public.scores (nick, score desc, created_at asc);

create index if not exists scores_fingerprint_recent_idx
	on public.scores (client_fingerprint, created_at desc);


-- ---------------------------------------------------------------------------
-- 3. IP do cliente e rate limit
-- ---------------------------------------------------------------------------
-- O PostgREST expoe os cabecalhos da requisicao no GUC request.headers.
create or replace function public.arkanoia_client_ip()
returns text
language sql
stable
as $$
	select split_part(
		coalesce(
			nullif(current_setting('request.headers', true)::json ->> 'cf-connecting-ip', ''),
			nullif(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''),
			'desconhecido'
		),
		',', 1
	);
$$;


create or replace function public.arkanoia_before_score_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
	fingerprint text;
	recent_count integer;
begin
	-- Guarda apenas um hash: o IP em claro nunca e persistido.
	fingerprint := md5(public.arkanoia_client_ip() || '::arkanoia-tjpr');

	new.client_fingerprint := fingerprint;
	new.created_at := now();          -- o cliente nao dita a data
	new.nick := upper(trim(new.nick));

	select count(*) into recent_count
	from public.scores s
	where s.client_fingerprint = fingerprint
		and s.created_at > now() - interval '1 minute';

	-- O prefixo PT faz o PostgREST responder com o status HTTP indicado.
	if recent_count >= 5 then
		raise exception 'muitos envios da mesma origem'
			using errcode = 'PT429';
	end if;

	return new;
end;
$$;

drop trigger if exists arkanoia_before_score_insert on public.scores;
create trigger arkanoia_before_score_insert
	before insert on public.scores
	for each row execute function public.arkanoia_before_score_insert();


-- ---------------------------------------------------------------------------
-- 4. RLS: apenas leitura publica e insercao anonima
-- ---------------------------------------------------------------------------
alter table public.scores enable row level security;

drop policy if exists scores_public_read on public.scores;
create policy scores_public_read
	on public.scores
	for select
	to anon, authenticated
	using (true);

drop policy if exists scores_public_insert on public.scores;
create policy scores_public_insert
	on public.scores
	for insert
	to anon, authenticated
	with check (true);

-- Nenhuma politica de UPDATE/DELETE: com RLS ativo, ambos ficam proibidos.


-- ---------------------------------------------------------------------------
-- 5. Privilegios por coluna
-- ---------------------------------------------------------------------------
revoke all on public.scores from anon, authenticated;

-- O cliente le somente o que a tabela do jogo mostra.
grant select (nick, score, created_at) on public.scores to anon, authenticated;

-- E escreve somente o que ele tem o direito de afirmar.
grant insert (nick, score, level, duration_ms) on public.scores to anon, authenticated;


-- ---------------------------------------------------------------------------
-- 6. View do ranking: a melhor pontuacao de cada nick
-- ---------------------------------------------------------------------------
-- Sem isso, um unico jogador bom ocuparia as dez posicoes do TOP 10.
-- security_invoker = true faz a view respeitar as permissoes de quem consulta.
create or replace view public.leaderboard
with (security_invoker = true) as
select distinct on (nick)
	nick,
	score,
	created_at
from public.scores
order by nick, score desc, created_at asc;

grant select on public.leaderboard to anon, authenticated;

comment on view public.leaderboard is
	'Melhor pontuacao por nick. O jogo consulta esta view; ordenacao e limite vem do PostgREST.';


-- ============================================================================
--  VERIFICACAO RAPIDA (opcional, rode depois)
-- ============================================================================
-- Deve inserir com sucesso:
--   insert into public.scores (nick, score, level, duration_ms)
--   values ('TESTE', 1500, 1, 65000);
--
-- Deve FALHAR (nick invalido):
--   insert into public.scores (nick, score) values ('inválido!', 10);
--
-- Deve FALHAR (implausivel: placar maximo em 1 segundo):
--   insert into public.scores (nick, score, duration_ms) values ('CHEAT', 999999, 1000);
--
-- Deve FALHAR (sem politica de update):
--   update public.scores set score = 999999 where nick = 'TESTE';
--
-- Ranking como o jogo enxerga:
--   select * from public.leaderboard order by score desc, created_at asc limit 10;
