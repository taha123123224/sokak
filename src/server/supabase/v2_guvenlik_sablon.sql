-- SOKAK: Operasyon — v2 GÜVENLİK (sunucu taraflı ekonomi)
-- Supabase > SQL Editor > New query > bu dosyanın TAMAMINI yapıştır > RUN.  (schema.sql'den sonra, bir kez)
--
-- Ne yapar?
--  * Oyuncu artık profilindeki altın / malzeme / silah / seviye / istatistik alanlarına DOĞRUDAN yazamaz.
--  * Satın alma, kasa açma, silah yükseltme, görev ödülü ve maç ödülü yalnızca sunucudaki
--    sokak_act() fonksiyonu üzerinden yapılır: fiyatlar, şanslar ve ödül sınırları sunucuda hesaplanır.
--  * Yeni hesaplar sunucunun verdiği başlangıç profiliyle açılır (istemcinin gönderdiği profil kabul edilmez).

-- ---------- katalog (fiyatlar, kasalar, görevler — oyundan otomatik üretildi) ----------
create table if not exists public.sokak_catalog (id int primary key, data jsonb not null);
insert into public.sokak_catalog (id, data) values (1, $CATALOG$__CATALOG__$CATALOG$::jsonb)
  on conflict (id) do update set data = excluded.data;
alter table public.sokak_catalog enable row level security;
revoke all on public.sokak_catalog from anon, authenticated;

-- ---------- profil yazma izinlerini kısıtla ----------
revoke insert, update, delete on public.profiles from anon, authenticated;
grant insert (id, username) on public.profiles to authenticated;
grant update (status, room, last_seen) on public.profiles to authenticated;

create or replace function public.sokak_profile_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.data := (select c.data->'default' from sokak_catalog c where c.id = 1) || jsonb_build_object('name', new.username);
  new.level := 1;
  return new;
end $$;
drop trigger if exists sokak_profile_defaults on public.profiles;
create trigger sokak_profile_defaults before insert on public.profiles
  for each row execute function public.sokak_profile_defaults();

-- ---------- yardımcılar ----------
create or replace function public._si(j jsonb, path text[]) returns bigint language sql immutable as $$
  select coalesce(floor((j #>> path)::numeric)::bigint, 0)
$$;

create or replace function public._pick(arr jsonb) returns text language sql volatile as $$
  select case when jsonb_typeof(arr) = 'array' and jsonb_array_length(arr) > 0
    then arr ->> floor(random() * jsonb_array_length(arr))::int else null end
$$;

create or replace function public._add_xp(p jsonb, amount bigint, out np jsonb, out ups int)
language plpgsql as $$
declare lv int; xp bigint;
begin
  lv := _si(p, '{level}'); xp := _si(p, '{xp}') + amount; ups := 0;
  while xp >= floor(1200 * power(lv, 1.35)) loop
    xp := xp - floor(1200 * power(lv, 1.35))::bigint;
    lv := lv + 1; ups := ups + 1;
    p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') + 500));
    p := jsonb_set(p, '{crates}', to_jsonb(_si(p, '{crates}') + 1));
  end loop;
  p := jsonb_set(p, '{xp}', to_jsonb(xp));
  np := jsonb_set(p, '{level}', to_jsonb(lv));
end $$;

create or replace function public._pay(p jsonb, n bigint) returns jsonb language plpgsql as $$
begin
  if n < 0 or _si(p, '{gold}') < n then raise exception 'Yetersiz altın!'; end if;
  return jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') - n));
end $$;

create or replace function public._crate_add(p jsonb, t text, n int) returns jsonb language plpgsql as $$
begin
  if t = 'sokak' then
    return jsonb_set(p, '{crates}', to_jsonb(greatest(0, _si(p, '{crates}') + n)));
  end if;
  if not (p ? 'crates2') or jsonb_typeof(p->'crates2') <> 'object' then p := jsonb_set(p, '{crates2}', '{}'); end if;
  return jsonb_set(p, array['crates2', t], to_jsonb(greatest(0, _si(p, array['crates2', t]) + n)));
end $$;

-- ---------- ana işlem fonksiyonu ----------
-- timed crate weapons: owned->w->exp (unix seconds). Expired ones move to p->expired (level/skins kept)
create or replace function public._expire(p jsonb, nowt float8) returns jsonb language plpgsql as $$
declare w text; d jsonb; i int; sl text; cnt int := 0;
begin
  if not (p ? 'expired') or jsonb_typeof(p->'expired') <> 'object' then p := jsonb_set(p, '{expired}', '{}'); end if;
  for w, d in select key, value from jsonb_each(p->'owned') loop
    if coalesce((d->>'exp')::float8, 0) > 0 and (d->>'exp')::float8 <= nowt then
      p := jsonb_set(p, array['expired', w], d - 'exp');
      p := p #- array['owned', w];
      cnt := cnt + 1;
    end if;
  end loop;
  if cnt > 0 and jsonb_typeof(p->'sets') = 'array' then
    for i in 0 .. jsonb_array_length(p->'sets') - 1 loop
      foreach sl in array array['ana', 'tabanca', 'bicak', 'bomba'] loop
        if (p->'sets'->i) ? sl and not (p->'owned' ? (p->'sets'->i->>sl)) then
          p := jsonb_set(p, array['sets', i::text, sl], to_jsonb((jsonb_build_object('ana','ak47','tabanca','glock','bicak','knife','bomba','frag'))->>sl));
        end if;
      end loop;
    end loop;
  end if;
  return p;
end $$;

create or replace function public._give_weapon(p jsonb, w text, expt float8) returns jsonb language plpgsql as $$
declare d jsonb;
begin
  if not (p ? 'expired') or jsonb_typeof(p->'expired') <> 'object' then p := jsonb_set(p, '{expired}', '{}'); end if;
  d := coalesce(p->'expired'->w, '{"lvl":0,"skins":["std"],"skin":"std"}'::jsonb);
  p := p #- array['expired', w];
  if expt > 0 then d := d || jsonb_build_object('exp', floor(expt)); else d := d - 'exp'; end if;
  return jsonb_set(p, array['owned', w], d);
end $$;

create or replace function public.sokak_act(a text, args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p jsonb; cat jsonb; res jsonb := '{}'::jsonb;
  id text; wid text; sk text; t text; price bigint; lvl int; ch int; ok boolean; nl int;
  cost jsonb; m text; r float8; it jsonb; arr jsonb; tot float8; pick float8; w float8; rr int;
  ms jsonb; k text; t0 float8; secs float8; kills int; head int; deaths int; won boolean; place int;
  shots bigint; hits bigint; is_full boolean; xp bigint; gold bigint; mats jsonb; ups int; i int;
  s jsonb; sets jsonb; cur jsonb; slot text; lst jsonb; slots jsonb; pid text; wp jsonb; nowt float8;
begin
  if uid is null then raise exception 'Giriş yapmalısın'; end if;
  select pr.data into p from profiles pr where pr.id = uid for update;
  if p is null then raise exception 'Profil bulunamadı'; end if;
  if exists (select 1 from profiles pr where pr.id = uid and pr.banned_until > now()) then
    raise exception 'Hesabın yasaklandı: %', (select coalesce(pr.ban_reason, '') from profiles pr where pr.id = uid);
  end if;
  select c.data into cat from sokak_catalog c where c.id = 1;
  nowt := extract(epoch from clock_timestamp());
  if not (p ? 'parts') or jsonb_typeof(p->'parts') <> 'object' then p := jsonb_set(p, '{parts}', '{}'); end if;
  if not (p ? 'chars') or jsonb_typeof(p->'chars') <> 'array' then p := jsonb_set(p, '{chars}', '["takim","deri","asker1"]'); end if;
  p := _expire(p, nowt);

  case a
  when 'buy_weapon' then
    id := args->>'id';
    if cat->'weapons'->id is null or (cat->'weapons'->id->>'throwable')::boolean or _si(cat, array['weapons', id, 'price']) <= 0 then
      raise exception 'Bu silah satılmıyor'; end if;
    if p->'owned' ? id and coalesce((p->'owned'->id->>'exp')::float8, 0) <= 0 then raise exception 'Bu silaha zaten sahipsin'; end if;
    price := _si(cat, array['weapons', id, 'price']);
    select f into k from jsonb_array_elements_text(cat->'featured') with ordinality as x(f, o)
      where not (p->'owned' ? f) order by o limit 1;
    if k = id then price := floor(price * 0.8); end if;
    p := _pay(p, price);
    if p->'owned' ? id then p := jsonb_set(p, array['owned', id], (p->'owned'->id) - 'exp');
    else p := _give_weapon(p, id, 0); end if;
    res := jsonb_build_object('id', id, 'price', price);

  when 'buy_skin' then
    wid := args->>'wid'; sk := args->>'skin';
    if not (p->'owned' ? wid) or cat->'skins'->sk is null or sk = 'std' then raise exception 'Geçersiz stil'; end if;
    if (p->'owned'->wid->'skins') ? sk then raise exception 'Bu stile zaten sahipsin'; end if;
    p := _pay(p, _si(cat, array['skins', sk, 'price']));
    p := jsonb_set(p, array['owned', wid, 'skins'], coalesce(p->'owned'->wid->'skins', '["std"]') || to_jsonb(sk));
    p := jsonb_set(p, array['owned', wid, 'skin'], to_jsonb(sk));

  when 'buy_part' then
    id := args->>'id';
    if cat->'parts'->id is null then raise exception 'Geçersiz eklenti'; end if;
    p := _pay(p, _si(cat, array['parts', id, 'price']));
    p := jsonb_set(p, array['parts', id], to_jsonb(_si(p, array['parts', id]) + 1));

  when 'buy_char' then
    id := args->>'id';
    if cat->'chars'->id is null then raise exception 'Geçersiz karakter'; end if;
    if (p->'chars') ? id or _si(cat, array['chars', id, 'price']) = 0 then raise exception 'Bu karaktere zaten sahipsin'; end if;
    p := _pay(p, _si(cat, array['chars', id, 'price']));
    p := jsonb_set(p, '{chars}', (p->'chars') || to_jsonb(id));
    p := jsonb_set(p, '{char}', to_jsonb(id));

  when 'buy_crate' then
    t := args->>'id';
    if cat->'crates'->t is null then raise exception 'Geçersiz kasa'; end if;
    p := _pay(p, _si(cat, array['crates', t, 'price']));
    p := _crate_add(p, t, 1);

  when 'buy_pack' then
    i := coalesce(floor((args->>'i')::numeric)::int, -1);
    if i < 0 or i >= jsonb_array_length(cat->'packs') then raise exception 'Geçersiz paket'; end if;
    arr := cat->'packs'->i;
    p := _pay(p, _si(arr, '{3}'));
    if arr->>1 = 'crate' then p := _crate_add(p, 'sokak', _si(arr, '{2}')::int);
    else p := jsonb_set(p, array['mats', arr->>1], to_jsonb(_si(p, array['mats', arr->>1]) + _si(arr, '{2}'))); end if;

  when 'open_crate' then
    t := args->>'id';
    if cat->'crates'->t is null then raise exception 'Geçersiz kasa'; end if;
    if (t = 'sokak' and _si(p, '{crates}') > 0) or (t <> 'sokak' and _si(p, array['crates2', t]) > 0) then
      p := _crate_add(p, t, -1);
    else
      p := _pay(p, _si(cat, array['crates', t, 'price']));
    end if;
    it := null;
    -- weapons first: crates are the main source of (mostly timed) weapons
    if jsonb_array_length(coalesce(cat->'crates'->t->'weapons', '[]')) > 0
       and random() < coalesce((cat->'crates'->t->>'wchance')::float8, 0) then
      r := random();
      it := jsonb_build_object('type', 'weapon', 'id', _pick(cat->'crates'->t->'weapons'),
        'days', case when r < 0.08 then 0 when r < 0.3 then 30 when r < 0.65 then 7 else 3 end);
    end if;
    r := random();
    if it is null and t <> 'efsane' and r < (case when t = 'sokak' then 0.3 else 0.18 end) then
      m := (array['demir','demir','krom','titanyum','kobalt'])[1 + floor(random() * 5)::int];
      it := jsonb_build_object('type', 'mat', 'id', m, 'n', (jsonb_build_object('demir',40,'krom',20,'titanyum',8,'kobalt',3)->>m)::int);
    elsif it is null and t <> 'efsane' and r < (case when t = 'sokak' then 0.5 else 0.3 end) then
      it := jsonb_build_object('type', 'gold', 'n', (array[500,800,1200,2500])[1 + floor(random() * 4)::int]);
    end if;
    if it is null and jsonb_array_length(coalesce(cat->'crates'->t->'parts', '[]')) > 0
       and random() < (case when t = 'eklenti' then 0.85 else 0.12 end) then
      it := jsonb_build_object('type', 'part', 'id', _pick(cat->'crates'->t->'parts'));
    end if;
    if it is null and jsonb_array_length(coalesce(cat->'crates'->t->'chars', '[]')) > 0 and random() < 0.06 then
      it := jsonb_build_object('type', 'char', 'id', _pick(cat->'crates'->t->'chars'));
    end if;
    if it is null then
      select o into wid from jsonb_object_keys(p->'owned') o
        where cat->'weapons'->o is not null and not (cat->'weapons'->o->>'throwable')::boolean order by random() limit 1;
      wid := coalesce(wid, 'ak47');
      arr := cat->'crates'->t->'skins';
      tot := 0;
      for sk in select jsonb_array_elements_text(arr) loop
        rr := _si(cat, array['skins', sk, 'rarity'])::int;
        tot := tot + (case when t = 'efsane' then (array[0, 0, 4, 1.2])[rr + 1] else (array[10, 5, 2, 0.5])[rr + 1] end);
      end loop;
      pick := random() * greatest(tot, 0.001);
      k := arr->>0;
      for sk in select jsonb_array_elements_text(arr) loop
        rr := _si(cat, array['skins', sk, 'rarity'])::int;
        pick := pick - (case when t = 'efsane' then (array[0, 0, 4, 1.2])[rr + 1] else (array[10, 5, 2, 0.5])[rr + 1] end);
        if pick <= 0 then k := sk; exit; end if;
      end loop;
      it := jsonb_build_object('type', 'skin', 'wid', wid, 'id', k);
    end if;
    -- grant
    case it->>'type'
    when 'part' then p := jsonb_set(p, array['parts', it->>'id'], to_jsonb(_si(p, array['parts', it->>'id']) + 1));
    when 'mat' then p := jsonb_set(p, array['mats', it->>'id'], to_jsonb(_si(p, array['mats', it->>'id']) + _si(it, '{n}')));
    when 'gold' then p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') + _si(it, '{n}')));
    when 'skin' then
      if (p->'owned' ? (it->>'wid')) and not ((p->'owned'->(it->>'wid')->'skins') ? (it->>'id')) then
        p := jsonb_set(p, array['owned', it->>'wid', 'skins'], (p->'owned'->(it->>'wid')->'skins') || to_jsonb(it->>'id'));
      else
        it := it || jsonb_build_object('dup', _si(cat, array['skins', it->>'id', 'price']) / 2);
        p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') + _si(it, '{dup}')));
      end if;
    when 'weapon' then
      wid := it->>'id'; nl := _si(it, '{days}')::int; price := _si(cat, array['weapons', wid, 'price']);
      if p->'owned' ? wid and coalesce((p->'owned'->wid->>'exp')::float8, 0) <= 0 then
        it := it || jsonb_build_object('dup', case when nl = 0 then price / 2 else greatest(150, price * nl / 90) end);
        p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') + _si(it, '{dup}')));
      elsif p->'owned' ? wid then
        if nl = 0 then p := jsonb_set(p, array['owned', wid], (p->'owned'->wid) - 'exp');
        else p := jsonb_set(p, array['owned', wid, 'exp'], to_jsonb(floor(greatest((p->'owned'->wid->>'exp')::float8, nowt) + nl * 86400))); end if;
        it := it || '{"ext":true}'::jsonb;
      else
        p := _give_weapon(p, wid, case when nl = 0 then 0 else nowt + nl * 86400 end);
      end if;
    when 'char' then
      if (p->'chars') ? (it->>'id') then
        it := it || '{"dup":1500}'::jsonb;
        p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') + 1500));
      else
        p := jsonb_set(p, '{chars}', (p->'chars') || to_jsonb(it->>'id'));
      end if;
    end case;
    res := it;

  when 'upgrade' then
    wid := args->>'wid';
    if not (p->'owned' ? wid) or cat->'weapons'->wid is null or (cat->'weapons'->wid->>'throwable')::boolean then
      raise exception 'Geçersiz silah'; end if;
    lvl := _si(p, array['owned', wid, 'lvl'])::int;
    if lvl >= jsonb_array_length(cat->'chances') then raise exception 'Silah en yüksek seviyede'; end if;
    cost := jsonb_build_object('gold', 400 * (lvl + 1), 'demir', 18 * (lvl + 1),
      'krom', case when lvl >= 1 then 10 * lvl else 0 end, 'titanyum', case when lvl >= 3 then 5 * (lvl - 2) else 0 end,
      'kobalt', case when lvl >= 5 then 4 * (lvl - 4) else 0 end);
    if _si(p, '{gold}') < _si(cost, '{gold}') then raise exception 'Yetersiz altın!'; end if;
    foreach m in array array['demir','krom','titanyum','kobalt'] loop
      if _si(p, array['mats', m]) < _si(cost, array[m]) then raise exception 'Yetersiz malzeme!'; end if;
    end loop;
    p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') - _si(cost, '{gold}')));
    foreach m in array array['demir','krom','titanyum','kobalt'] loop
      p := jsonb_set(p, array['mats', m], to_jsonb(_si(p, array['mats', m]) - _si(cost, array[m])));
    end loop;
    ch := floor((cat->'chances'->>lvl)::numeric)::int;
    ok := (1 + floor(random() * 100)::int) <= ch;
    nl := case when ok then lvl + 1 when lvl >= 5 then lvl - 1 else lvl end;
    p := jsonb_set(p, array['owned', wid, 'lvl'], to_jsonb(nl));
    res := jsonb_build_object('success', ok, 'lvl', nl, 'prev', lvl);

  when 'claim_mission' then
    id := args->>'id';
    select x into ms from jsonb_array_elements(cat->'missions') x where x->>'id' = id;
    if ms is null then raise exception 'Görev bulunamadı'; end if;
    if p->'missions'->'claimed' ? id then raise exception 'Ödül zaten alındı'; end if;
    if _si(p, array['missions', ms->>'key']) < _si(ms, '{goal}') then raise exception 'Görev henüz tamamlanmadı'; end if;
    for k in select jsonb_object_keys(ms->'reward') loop
      if k = 'gold' then p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') + _si(ms, array['reward', k])));
      else p := jsonb_set(p, array['mats', k], to_jsonb(_si(p, array['mats', k]) + _si(ms, array['reward', k]))); end if;
    end loop;
    p := jsonb_set(p, array['missions', 'claimed', id], 'true');

  when 'match_start' then
    p := jsonb_set(p, '{_t0}', to_jsonb(nowt));

  when 'match_end' then
    t0 := coalesce((p->>'_t0')::float8, 0);
    p := p - '_t0';
    secs := case when t0 > 0 then least(greatest(nowt - t0, 0), 1800) else 0 end;
    kills := least(greatest(coalesce(floor((args->>'kills')::numeric)::int, 0), 0), least(50, floor(secs / 6)::int));
    head := least(greatest(coalesce(floor((args->>'head')::numeric)::int, 0), 0), kills);
    deaths := least(greatest(coalesce(floor((args->>'deaths')::numeric)::int, 0), 0), 200);
    won := coalesce((args->>'won')::boolean, false) and secs >= 60;
    place := least(greatest(coalesce(floor((args->>'place')::numeric)::int, 10), 1), 20);
    shots := least(greatest(coalesce(floor((args->>'shots')::numeric)::bigint, 0), 0), floor(secs * 15)::bigint);
    hits := least(greatest(coalesce(floor((args->>'hits')::numeric)::bigint, 0), 0), shots);
    is_full := secs >= 45;
    if is_full then
      xp := 200 + kills * 100 + head * 50 + (case when won then 600 else 0 end) + greatest(0, 4 - place) * 100;
      gold := 150 + kills * 45 + (case when won then 400 else 0 end);
      mats := jsonb_build_object('demir', 6 + floor(random() * 9)::int + kills,
        'krom', case when random() < 0.75 then 2 + floor(random() * 5)::int else 0 end,
        'titanyum', case when random() < 0.35 + (case when won then 0.2 else 0 end) then 1 + floor(random() * 3)::int else 0 end,
        'kobalt', case when random() < 0.12 + (case when won then 0.1 else 0 end) then 1 else 0 end);
    else
      xp := kills * 50; gold := kills * 20;
      mats := '{"demir":0,"krom":0,"titanyum":0,"kobalt":0}';
    end if;
    select np, x.ups into p, ups from _add_xp(p, xp) x;
    -- competitive rank points (same rule as econ.gd rp_delta); bot / unranked matches count half
    i := 0;
    if is_full then
      if won then i := 18 + least(kills, 20) / 2 + (case when head >= 5 then 3 else 0 end);
      else i := -(14 - least(kills, 12) / 2); end if;
      -- "ranked" is only believed when the player really is in an online room with other players
      if not (coalesce((args->>'ranked')::boolean, false) and exists (
          select 1 from profiles pr join rooms r on r.code = pr.room
          where pr.id = uid and r.players >= 2 and r.updated_at > now() - interval '45 minutes')) then
        i := trunc(i / 2.0)::int;
      end if;
    end if;
    lvl := _si(p, '{rp}')::int;
    p := jsonb_set(p, '{rp}', to_jsonb(greatest(0, lvl + i)));
    p := jsonb_set(p, '{rp_peak}', to_jsonb(greatest(_si(p, '{rp_peak}'), _si(p, '{rp}'))));
    p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') + gold));
    foreach m in array array['demir','krom','titanyum','kobalt'] loop
      p := jsonb_set(p, array['mats', m], to_jsonb(_si(p, array['mats', m]) + _si(mats, array[m])));
    end loop;
    p := jsonb_set(p, '{stats,kills}', to_jsonb(_si(p, '{stats,kills}') + kills));
    p := jsonb_set(p, '{stats,headshots}', to_jsonb(_si(p, '{stats,headshots}') + head));
    p := jsonb_set(p, '{stats,deaths}', to_jsonb(_si(p, '{stats,deaths}') + deaths));
    p := jsonb_set(p, '{stats,shots}', to_jsonb(_si(p, '{stats,shots}') + shots));
    p := jsonb_set(p, '{stats,hits}', to_jsonb(_si(p, '{stats,hits}') + hits));
    p := jsonb_set(p, '{missions,kills}', to_jsonb(_si(p, '{missions,kills}') + kills));
    p := jsonb_set(p, '{missions,head}', to_jsonb(_si(p, '{missions,head}') + head));
    if is_full then
      p := jsonb_set(p, '{stats,matches}', to_jsonb(_si(p, '{stats,matches}') + 1));
      p := jsonb_set(p, '{missions,matches}', to_jsonb(_si(p, '{missions,matches}') + 1));
    end if;
    if won then
      p := jsonb_set(p, '{stats,wins}', to_jsonb(_si(p, '{stats,wins}') + 1));
      p := jsonb_set(p, '{missions,wins}', to_jsonb(_si(p, '{missions,wins}') + 1));
    end if;
    res := jsonb_build_object('xp', xp, 'gold', gold, 'mats', mats, 'ups', ups, 'won', won,
      'rp', _si(p, '{rp}'), 'rp_old', lvl, 'rpd', _si(p, '{rp}') - lvl);

  when 'sync' then
    s := args;
    if jsonb_typeof(s->'sets') = 'array' then
      sets := '[]';
      for i in 0 .. floor((cat->>'sets')::numeric)::int - 1 loop
        cur := coalesce(p->'sets'->i, p->'sets'->0, '{}');
        if jsonb_typeof(s->'sets'->i) = 'object' then
          foreach slot in array array['ana','tabanca','bicak','bomba'] loop
            wid := s->'sets'->i->>slot;
            if wid is not null and (p->'owned' ? wid) and cat->'weapons'->wid->>'cat' = slot then
              cur := jsonb_set(cur, array[slot], to_jsonb(wid));
            end if;
          end loop;
        end if;
        sets := sets || jsonb_build_array(cur);
      end loop;
      p := jsonb_set(p, '{sets}', sets);
    end if;
    if s ? 'active_set' then
      p := jsonb_set(p, '{active_set}', to_jsonb(least(greatest(coalesce(floor((s->>'active_set')::numeric)::int, 0), 0), floor((cat->>'sets')::numeric)::int - 1)));
    end if;
    if s ? 'char' then
      id := s->>'char';
      if id = '' or (cat->'chars'->id is not null and (_si(cat, array['chars', id, 'price']) = 0 or (p->'chars') ? id)) then
        p := jsonb_set(p, '{char}', to_jsonb(coalesce(id, '')));
      end if;
    end if;
    if jsonb_typeof(s->'skins') = 'object' then
      for wid in select jsonb_object_keys(s->'skins') loop
        sk := s->'skins'->>wid;
        if p->'owned' ? wid and coalesce(p->'owned'->wid->'skins', '["std"]') ? sk then
          p := jsonb_set(p, array['owned', wid, 'skin'], to_jsonb(sk));
        end if;
      end loop;
    end if;
    if jsonb_typeof(s->'wparts') = 'object' then
      wp := '{}';
      for wid in select jsonb_object_keys(s->'wparts') loop
        if not (p->'owned' ? wid) or jsonb_typeof(s->'wparts'->wid) <> 'array' then continue; end if;
        lst := '[]'; slots := '{}';
        for pid in select jsonb_array_elements_text(s->'wparts'->wid) loop
          if cat->'parts'->pid is null or _si(p, array['parts', pid]) <= 0
             or not ((cat->'parts'->pid->'fits') ? wid) or slots ? (cat->'parts'->pid->>'slot') then continue; end if;
          slots := slots || jsonb_build_object(cat->'parts'->pid->>'slot', true);
          lst := lst || to_jsonb(pid);
        end loop;
        if jsonb_array_length(lst) > 0 then wp := wp || jsonb_build_object(wid, lst); end if;
      end loop;
      p := jsonb_set(p, '{wparts}', wp);
    end if;

  when 'reset' then
    p := (cat->'default') || jsonb_build_object('name', p->>'name');

  when 'get' then
    null;

  when 'mail_ack' then
    p := jsonb_set(p, '{mail}', '[]'::jsonb);

  else
    raise exception 'Bilinmeyen işlem';
  end case;

  update profiles set data = p, level = _si(p, '{level}')::int, last_seen = now() where profiles.id = uid;
  return jsonb_build_object('profile', p, 'res', res);
end $$;

revoke all on function public.sokak_act(text, jsonb) from public, anon;
grant execute on function public.sokak_act(text, jsonb) to authenticated;

-- =====================================================================================
-- v2.6 YÖNETİCİ (ADMIN) SİSTEMİ
-- Yetki sunucuda tutulur; oyun dosyalarında hiçbir şifre yoktur.
-- Kurucu hesap: kullanıcı adı "sokakoperasyon" olan hesap (önce oyunda bu adla KAYIT OL, sonra bu SQL'i çalıştır).
-- =====================================================================================
create table if not exists public.sokak_admins (user_id uuid primary key references public.profiles(id) on delete cascade);
alter table public.sokak_admins enable row level security;
revoke all on public.sokak_admins from anon, authenticated;
insert into public.sokak_admins (user_id)
  select id from public.profiles where lower(username) = 'sokakoperasyon'
  on conflict do nothing;

alter table public.profiles add column if not exists banned_until timestamptz;
alter table public.profiles add column if not exists ban_reason text;

create table if not exists public.sokak_announcements (
  id bigserial primary key, text text not null check (length(text) between 1 and 300),
  created_at timestamptz not null default now());
alter table public.sokak_announcements enable row level security;
drop policy if exists "announcements readable" on public.sokak_announcements;
create policy "announcements readable" on public.sokak_announcements for select to authenticated using (true);
revoke insert, update, delete on public.sokak_announcements from anon, authenticated;

-- every admin action is written here (only readable through sokak_admin('log'))
create table if not exists public.sokak_admin_log (
  id bigserial primary key, admin_id uuid, action text not null, target text, info jsonb,
  at timestamptz not null default now());
alter table public.sokak_admin_log enable row level security;
revoke all on public.sokak_admin_log from anon, authenticated;

create or replace function public._is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from sokak_admins where user_id = auth.uid())
$$;

-- gift helper: adds gold / materials / crates / skin / weapon to one profile and drops a mail note
create or replace function public._gift(p jsonb, g jsonb, nowt float8) returns jsonb language plpgsql as $$
declare m text; wid text; sk text; days int;
begin
  if _si(g, '{gold}') > 0 then p := jsonb_set(p, '{gold}', to_jsonb(_si(p, '{gold}') + least(_si(g, '{gold}'), 10000000))); end if;
  foreach m in array array['demir','krom','titanyum','kobalt'] loop
    if _si(g, array['mats', m]) > 0 then
      p := jsonb_set(p, array['mats', m], to_jsonb(_si(p, array['mats', m]) + least(_si(g, array['mats', m]), 100000)));
    end if;
  end loop;
  if _si(g, '{crates}') > 0 then p := jsonb_set(p, '{crates}', to_jsonb(_si(p, '{crates}') + least(_si(g, '{crates}'), 1000))); end if;
  if g ? 'crate_type' and _si(g, '{crate_n}') > 0 then p := _crate_add(p, g->>'crate_type', least(_si(g, '{crate_n}'), 1000)::int); end if;
  wid := g->>'weapon';
  if wid is not null and wid <> '' then
    days := coalesce(floor((g->>'days')::numeric)::int, 0);
    if p->'owned' ? wid then
      if days = 0 then p := jsonb_set(p, array['owned', wid], (p->'owned'->wid) - 'exp');
      elsif coalesce((p->'owned'->wid->>'exp')::float8, 0) > 0 then
        p := jsonb_set(p, array['owned', wid, 'exp'], to_jsonb(floor(greatest((p->'owned'->wid->>'exp')::float8, nowt) + days * 86400)));
      end if;
    else
      p := _give_weapon(p, wid, case when days = 0 then 0 else nowt + days * 86400 end);
    end if;
  end if;
  sk := g->>'skin'; wid := coalesce(g->>'skin_wid', g->>'weapon');
  if sk is not null and sk <> '' and wid is not null and p->'owned' ? wid and not ((p->'owned'->wid->'skins') ? sk) then
    p := jsonb_set(p, array['owned', wid, 'skins'], coalesce(p->'owned'->wid->'skins', '["std"]') || to_jsonb(sk));
  end if;
  p := jsonb_set(p, '{mail}', coalesce(p->'mail', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
    't', floor(nowt), 'msg', coalesce(g->>'msg', 'Yöneticiden hediye!'), 'gift', g - 'msg')));
  return p;
end $$;

create or replace function public.sokak_admin(a text, args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare res jsonb := '{}'::jsonb; target uuid; hrs numeric; nowt float8; r record; n int := 0; q text;
begin
  if a = 'whoami' then return jsonb_build_object('admin', _is_admin()); end if;
  if not _is_admin() then raise exception 'Yetkin yok'; end if;
  nowt := extract(epoch from clock_timestamp());
  if a not in ('stats', 'users', 'anns', 'log', 'whoami') then
    insert into sokak_admin_log (admin_id, action, target, info)
      values (auth.uid(), a, coalesce(args->>'id', ''), args - 'id');
  end if;
  case a
  when 'stats' then
    select jsonb_build_object(
      'online', (select count(*) from profiles where last_seen > now() - interval '90 seconds'),
      'in_match', (select count(*) from profiles where last_seen > now() - interval '90 seconds' and status = 'match'),
      'total', (select count(*) from profiles),
      'today', (select count(*) from profiles where created_at > now() - interval '1 day'),
      'banned', (select count(*) from profiles where banned_until > now()),
      'rooms', (select count(*) from rooms where updated_at > now() - interval '2 minutes'),
      'week', (select count(*) from profiles where created_at > now() - interval '7 days'),
      'active_day', (select count(*) from profiles where last_seen > now() - interval '1 day'),
      'gold_total', (select coalesce(sum(_si(data, '{gold}')), 0) from profiles),
      'top', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (select username, _si(data, '{rp}') as rp, level
                from profiles order by _si(data, '{rp}') desc limit 5) t)) into res;
  when 'anns' then
    select coalesce(jsonb_agg(x order by x.id desc), '[]'::jsonb) into res
      from (select id, text, created_at from sokak_announcements order by id desc limit 20) x;
  when 'ann_del' then
    delete from sokak_announcements where id = floor((args->>'ann')::numeric)::bigint;
  when 'log' then
    select coalesce(jsonb_agg(x order by x.id desc), '[]'::jsonb) into res from (
      select l.id, l.action, l.at, l.info, coalesce(t.username, l.target) as target, ad.username as admin
      from sokak_admin_log l left join profiles t on t.id::text = l.target left join profiles ad on ad.id = l.admin_id
      order by l.id desc limit 60) x;
  when 'users' then
    q := replace(replace(replace(left(coalesce(args->>'q', ''), 32), '\', ''), '%', ''), '_', '\_');
    select coalesce(jsonb_agg(x), '[]'::jsonb) into res from (
      select id, username, level, status, last_seen, created_at, banned_until, ban_reason,
        _si(data, '{gold}') as gold, _si(data, '{rp}') as rp, _si(data, '{stats,kills}') as kills,
        _si(data, '{stats,deaths}') as deaths, _si(data, '{stats,wins}') as wins, _si(data, '{stats,matches}') as matches,
        _si(data, '{xp}') as xp,
        (select count(*) from jsonb_object_keys(case when jsonb_typeof(data->'owned') = 'object' then data->'owned' else '{}'::jsonb end)) as weapons,
        exists (select 1 from sokak_admins s where s.user_id = profiles.id) as admin
      from profiles
      where (q = '' or username ilike q || '%')
        and (coalesce(args->>'f', '') <> 'online' or last_seen > now() - interval '90 seconds')
        and (coalesce(args->>'f', '') <> 'banned' or banned_until > now())
      order by (last_seen > now() - interval '90 seconds') desc, last_seen desc nulls last limit 80) x;
  when 'ban' then
    target := (args->>'id')::uuid;
    if exists (select 1 from sokak_admins where user_id = target) then raise exception 'Yönetici yasaklanamaz'; end if;
    hrs := coalesce((args->>'hours')::numeric, 0);
    update profiles set banned_until = case when hrs <= 0 then 'infinity'::timestamptz else now() + hrs * interval '1 hour' end,
      ban_reason = left(coalesce(args->>'reason', 'Kurallara aykırı davranış'), 120) where id = target;
  when 'unban' then
    update profiles set banned_until = null, ban_reason = null where id = (args->>'id')::uuid;
  when 'delete' then
    target := (args->>'id')::uuid;
    if exists (select 1 from sokak_admins where user_id = target) then raise exception 'Yönetici silinemez'; end if;
    delete from auth.users where id = target;
  when 'announce' then
    insert into sokak_announcements (text) values (left(args->>'text', 300));
  when 'gift' then
    if args->>'id' = 'all' then
      for r in select id, data from profiles where banned_until is null or banned_until < now() loop
        update profiles set data = _gift(r.data, args->'gift', nowt) where id = r.id;
        n := n + 1;
      end loop;
    else
      update profiles set data = _gift(data, args->'gift', nowt) where id = (args->>'id')::uuid;
      n := 1;
    end if;
    res := jsonb_build_object('count', n);
  else
    raise exception 'Bilinmeyen yönetici işlemi';
  end case;
  return jsonb_build_object('ok', true, 'res', res);
end $$;
revoke all on function public.sokak_admin(text, jsonb) from public, anon;
grant execute on function public.sokak_admin(text, jsonb) to authenticated;
revoke all on function public._gift(jsonb, jsonb, float8) from public, anon, authenticated;
