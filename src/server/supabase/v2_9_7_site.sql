-- SOKAK: Operasyon — web sitesi canlı sıralama ve sayaçlar
-- Supabase > SQL Editor > New query > bu dosyanın tamamını yapıştır > RUN (bir kez).
-- Site yalnızca bu iki fonksiyonu çağırır. Fonksiyonlar sadece kullanıcı adı, seviye, RP ve maç istatistiklerini
-- döndürür (e-posta, envanter, para vb. asla dışarı çıkmaz); tablolar herkese açılmaz.

create or replace function public.site_leaderboard(sort_key text default 'rp', lim int default 50)
returns table(username text, level int, rp int, kills int, deaths int, wins int, matches int, online boolean)
language sql stable security definer set search_path = public as $$
  select p.username,
         p.level,
         coalesce(round((p.data->>'rp')::numeric), 0)::int,
         coalesce(round((p.data->'stats'->>'kills')::numeric), 0)::int,
         coalesce(round((p.data->'stats'->>'deaths')::numeric), 0)::int,
         coalesce(round((p.data->'stats'->>'wins')::numeric), 0)::int,
         coalesce(round((p.data->'stats'->>'matches')::numeric), 0)::int,
         p.last_seen > now() - interval '75 seconds'
  from public.profiles p
  where coalesce(p.banned_until, 'epoch'::timestamptz) < now()
  order by case sort_key
             when 'level' then p.level::numeric
             when 'kills' then coalesce((p.data->'stats'->>'kills')::numeric, 0)
             when 'wins'  then coalesce((p.data->'stats'->>'wins')::numeric, 0)
             else coalesce((p.data->>'rp')::numeric, 0)
           end desc,
           p.level desc, p.username
  limit least(greatest(coalesce(lim, 50), 1), 100);
$$;

create or replace function public.site_stats()
returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'online',   (select count(*) from public.profiles where last_seen > now() - interval '75 seconds'),
    'in_match', (select count(*) from public.profiles where last_seen > now() - interval '75 seconds' and status = 'match'),
    'players',  (select count(*) from public.profiles),
    'rooms',    (select count(*) from public.rooms where updated_at > now() - interval '120 seconds' and private = false)
  );
$$;

revoke all on function public.site_leaderboard(text, int) from public;
revoke all on function public.site_stats() from public;
grant execute on function public.site_leaderboard(text, int) to anon, authenticated;
grant execute on function public.site_stats() to anon, authenticated;
