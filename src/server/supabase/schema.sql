-- SOKAK: Operasyon — online backend (Supabase, free tier)
-- Paste everything into Supabase > SQL Editor > New query > RUN (once).

-- ---------- profiles: one row per account (username + cloud save) ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (username ~ '^[A-Za-z0-9_ÇĞİÖŞÜçğıöşü]{3,16}$'),
  data jsonb not null default '{}'::jsonb,          -- full player save (gold, weapons, skins, levels...)
  level int not null default 1,
  status text not null default 'online',            -- online | lobby | match
  room text,                                        -- room code while in a room
  last_seen timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower on public.profiles (lower(username));

-- ---------- friendships ----------
create table if not exists public.friendships (
  id bigint generated always as identity primary key,
  requester uuid not null references public.profiles(id) on delete cascade,
  addressee uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  unique (requester, addressee),
  check (requester <> addressee)
);

-- ---------- room invites ----------
create table if not exists public.invites (
  id bigint generated always as identity primary key,
  sender uuid not null references public.profiles(id) on delete cascade,
  receiver uuid not null references public.profiles(id) on delete cascade,
  room text not null,
  room_name text not null default '',
  created_at timestamptz not null default now()
);

-- ---------- public room list (rooms announce themselves while open) ----------
create table if not exists public.rooms (
  code text primary key,
  host uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  map text not null,
  mode text not null,
  players int not null default 1,
  max_players int not null default 10,
  private boolean not null default false,
  state text not null default 'lobby',
  updated_at timestamptz not null default now()
);

-- ---------- row level security ----------
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.invites enable row level security;
alter table public.rooms enable row level security;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select to authenticated using (true);
drop policy if exists "own profile insert" on public.profiles;
create policy "own profile insert" on public.profiles for insert to authenticated with check (auth.uid() = id);
drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update to authenticated using (auth.uid() = id);

drop policy if exists "see own friendships" on public.friendships;
create policy "see own friendships" on public.friendships for select to authenticated using (auth.uid() in (requester, addressee));
drop policy if exists "send request" on public.friendships;
create policy "send request" on public.friendships for insert to authenticated with check (auth.uid() = requester and status = 'pending');
drop policy if exists "accept request" on public.friendships;
create policy "accept request" on public.friendships for update to authenticated using (auth.uid() = addressee);
drop policy if exists "remove friendship" on public.friendships;
create policy "remove friendship" on public.friendships for delete to authenticated using (auth.uid() in (requester, addressee));

drop policy if exists "see my invites" on public.invites;
create policy "see my invites" on public.invites for select to authenticated using (auth.uid() in (sender, receiver));
drop policy if exists "invite friends" on public.invites;
create policy "invite friends" on public.invites for insert to authenticated with check (
  auth.uid() = sender and exists (
    select 1 from public.friendships f where f.status = 'accepted' and
      ((f.requester = sender and f.addressee = receiver) or (f.requester = receiver and f.addressee = sender))));
drop policy if exists "delete my invites" on public.invites;
create policy "delete my invites" on public.invites for delete to authenticated using (auth.uid() in (sender, receiver));

drop policy if exists "rooms readable" on public.rooms;
create policy "rooms readable" on public.rooms for select to authenticated using (true);
drop policy if exists "host manages room" on public.rooms;
create policy "host manages room" on public.rooms for all to authenticated using (auth.uid() = host) with check (auth.uid() = host);

-- ---------- helper: friends list with online state in one call ----------
create or replace function public.my_friends()
returns table (friendship_id bigint, user_id uuid, username text, level int, status text, room text, online boolean, pending boolean, incoming boolean)
language sql stable security definer set search_path = public as $$
  select f.id,
         p.id, p.username, p.level, p.status, p.room,
         (p.last_seen > now() - interval '75 seconds') as online,
         (f.status = 'pending') as pending,
         (f.addressee = auth.uid()) as incoming
  from friendships f
  join profiles p on p.id = case when f.requester = auth.uid() then f.addressee else f.requester end
  where auth.uid() in (f.requester, f.addressee)
  order by (p.last_seen > now() - interval '75 seconds') desc, p.username;
$$;
grant execute on function public.my_friends() to authenticated;

-- ---------- helper: is a username free? (callable before signing up) ----------
create or replace function public.username_free(name text)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles where lower(username) = lower(name));
$$;
grant execute on function public.username_free(text) to anon, authenticated;

-- stale rooms are hidden by the client (updated_at older than 2 minutes); invites older than 10 minutes are ignored.
