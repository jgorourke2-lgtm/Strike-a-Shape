-- Strike a Shape: ranked lobby storage. Paste this whole file into
-- Supabase > SQL Editor > New query > Run.

-- One row per lobby. `data` holds the whole lobby as JSON.
create table if not exists public.lobbies (
  code text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Anyone with the (public) anon key can read and write lobbies. Fine for a class game.
grant select, insert, update, delete on public.lobbies to anon, authenticated;
alter table public.lobbies enable row level security;
drop policy if exists "lobbies open access" on public.lobbies;
create policy "lobbies open access" on public.lobbies
  for all to anon, authenticated using (true) with check (true);

-- Updates one or more fields at once, using paths like "players/abc123/score".
-- A null value removes that field. Each update locks the row, so
-- simultaneous updates from several players can't overwrite each other.
create or replace function public.patch_lobby(p_code text, p_updates jsonb)
returns void
language plpgsql
as $$
declare
  k text;
  v jsonb;
  path text[];
begin
  for k, v in select * from jsonb_each(p_updates) loop
    path := string_to_array(k, '/');
    if v = 'null'::jsonb then
      update public.lobbies set data = data #- path, updated_at = now() where code = p_code;
    else
      update public.lobbies set data = jsonb_set(data, path, v, true), updated_at = now() where code = p_code;
    end if;
  end loop;
end;
$$;

grant execute on function public.patch_lobby(text, jsonb) to anon, authenticated;

-- Server clock, so every player's countdown lines up.
create or replace function public.server_time()
returns bigint
language sql
stable
as $$
  select (extract(epoch from now()) * 1000)::bigint;
$$;

grant execute on function public.server_time() to anon, authenticated;

-- Live updates: send lobby changes to every connected player.
do $$
begin
  alter publication supabase_realtime add table public.lobbies;
exception when duplicate_object then null;
end $$;

-- Optional housekeeping: remove lobbies untouched for a day.
-- delete from public.lobbies where updated_at < now() - interval '1 day';
