-- Sincronizacao de rodadas entre Cidade e Central.
-- Executar no SQL Editor do Supabase, nesta ordem, antes de abrir a nova build.

-- 1. Identificador da rodada publicada pela Cidade.
alter table public.salas
	add column if not exists rodada_atual integer not null default 0;

-- 2. Estado da rodada: aguardando | ativa | concluida | perdida.
alter table public.salas
	add column if not exists estado_rodada text not null default 'aguardando';

-- 3. Posicao do abrigo gerado pela Cidade ([x, y, z]).
alter table public.salas
	add column if not exists abrigo_position jsonb;

-- 4. Sinal de derrota da partida (vida = 0 ou tempo esgotado).
--    A Cidade grava true junto com estado_rodada = 'perdida'. A Central le
--    este campo e abre a tela de derrota. Um PATCH de rodada normal da Cidade
--    envia o campo como false, liberando a sala para uma nova partida.
alter table public.salas
	add column if not exists partida_perdida boolean not null default false;

-- 5. Opcional: alinhar salas que ja estavam em partida antes da migracao.
--    Novas partidas publicarao a rodada 1 assim que o mundo ficar pronto.
update public.salas
set rodada_atual = 1,
	estado_rodada = 'ativa'
where iniciado = true
	and inicio_timer is not null
	and rodada_atual = 0;

-- Nao e necessario RPC: a Cidade envia rodada, estado, timer, pontos, eventos,
-- abrigo e partida_perdida no mesmo PATCH da mesma linha, e a Central le tudo
-- em um unico GET. As colunas novas herdam os grants e as politicas RLS
-- existentes da tabela.
