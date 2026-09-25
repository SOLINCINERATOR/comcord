-- COMCORD DATABASE
-- Run this entire file in Supabase SQL Editor.
-- It is designed for a fresh Supabase project.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null,
  avatar_url text,
  banner_url text,
  status text not null default 'online' check (status in ('online','idle','dnd','invisible','offline')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  unique(sender_id, receiver_id)
);

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (user_a <> user_b),
  unique(user_a, user_b)
);

create table if not exists public.dm_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (user_a <> user_b)
);

create table if not exists public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text,
  attachment_url text,
  attachment_type text,
  created_at timestamptz not null default now()
);

create table if not exists public.servers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  icon_url text,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  max_members integer not null default 100 check (max_members between 1 and 10000),
  invite_code text not null unique default encode(gen_random_bytes(8),'hex'),
  created_at timestamptz not null default now()
);

create table if not exists public.server_members (
  server_id uuid not null references public.servers(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  nickname text,
  joined_at timestamptz not null default now(),
  primary key(server_id,user_id)
);

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.servers(id) on delete cascade,
  name text not null,
  color text default '#ffffff',
  permissions jsonb not null default '{}'::jsonb,
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.member_roles (
  server_id uuid not null references public.servers(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  primary key(server_id,user_id,role_id)
);

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.servers(id) on delete cascade,
  name text not null,
  type text not null default 'text' check(type in ('text','voice','category')),
  parent_id uuid references public.channels(id) on delete set null,
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.channel_messages (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text,
  attachment_url text,
  attachment_type text,
  created_at timestamptz not null default now()
);

-- Create profile automatically when an Auth account is created.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  uname text;
begin
  uname := coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1));
  insert into public.profiles(id, username, display_name)
  values(new.id, uname, uname)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Basic helper: join an invite while enforcing the member limit atomically.
create or replace function public.join_server_by_invite(p_invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.servers%rowtype;
  current_count integer;
begin
  select * into s from public.servers where invite_code = p_invite_code for update;
  if not found then
    raise exception 'Invalid invite';
  end if;

  if exists(select 1 from public.server_members where server_id=s.id and user_id=auth.uid()) then
    return s.id;
  end if;

  select count(*) into current_count from public.server_members where server_id=s.id;
  if current_count >= s.max_members then
    raise exception 'This server is full';
  end if;

  insert into public.server_members(server_id,user_id) values(s.id,auth.uid());
  return s.id;
end;
$$;

-- RLS
alter table public.profiles enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.dm_conversations enable row level security;
alter table public.dm_messages enable row level security;
alter table public.servers enable row level security;
alter table public.server_members enable row level security;
alter table public.roles enable row level security;
alter table public.member_roles enable row level security;
alter table public.channels enable row level security;
alter table public.channel_messages enable row level security;

-- Profiles
drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated" on public.profiles for select to authenticated using (true);
drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());

-- Friend requests
drop policy if exists "friend_requests_select_own" on public.friend_requests;
create policy "friend_requests_select_own" on public.friend_requests for select to authenticated using (sender_id=auth.uid() or receiver_id=auth.uid());
drop policy if exists "friend_requests_insert_self" on public.friend_requests;
create policy "friend_requests_insert_self" on public.friend_requests for insert to authenticated with check (sender_id=auth.uid());
drop policy if exists "friend_requests_update_receiver" on public.friend_requests;
create policy "friend_requests_update_receiver" on public.friend_requests for update to authenticated using (receiver_id=auth.uid()) with check (receiver_id=auth.uid());

-- Friendships
drop policy if exists "friendships_select_own" on public.friendships;
create policy "friendships_select_own" on public.friendships for select to authenticated using (user_a=auth.uid() or user_b=auth.uid());

-- DMs
drop policy if exists "dm_conversations_own" on public.dm_conversations;
create policy "dm_conversations_own" on public.dm_conversations for all to authenticated
using (user_a=auth.uid() or user_b=auth.uid())
with check (user_a=auth.uid() or user_b=auth.uid());

drop policy if exists "dm_messages_own" on public.dm_messages;
create policy "dm_messages_own" on public.dm_messages for all to authenticated
using (exists(select 1 from public.dm_conversations c where c.id=conversation_id and (c.user_a=auth.uid() or c.user_b=auth.uid())))
with check (sender_id=auth.uid() and exists(select 1 from public.dm_conversations c where c.id=conversation_id and (c.user_a=auth.uid() or c.user_b=auth.uid())));

-- Servers
drop policy if exists "servers_read_members" on public.servers;
create policy "servers_read_members" on public.servers for select to authenticated
using (owner_id=auth.uid() or exists(select 1 from public.server_members m where m.server_id=id and m.user_id=auth.uid()));
drop policy if exists "servers_create" on public.servers;
create policy "servers_create" on public.servers for insert to authenticated with check (owner_id=auth.uid());
drop policy if exists "servers_update_owner" on public.servers;
create policy "servers_update_owner" on public.servers for update to authenticated using (owner_id=auth.uid()) with check (owner_id=auth.uid());

-- Server members
drop policy if exists "members_read_members" on public.server_members;
create policy "members_read_members" on public.server_members for select to authenticated
using (exists(select 1 from public.server_members x where x.server_id=server_id and x.user_id=auth.uid()));
drop policy if exists "members_insert_self" on public.server_members;
create policy "members_insert_self" on public.server_members for insert to authenticated with check (user_id=auth.uid());

-- Roles/channels/messages
drop policy if exists "roles_read_members" on public.roles;
create policy "roles_read_members" on public.roles for select to authenticated using (exists(select 1 from public.server_members m where m.server_id=server_id and m.user_id=auth.uid()));
drop policy if exists "member_roles_read_members" on public.member_roles;
create policy "member_roles_read_members" on public.member_roles for select to authenticated using (user_id=auth.uid() or exists(select 1 from public.server_members m where m.server_id=server_id and m.user_id=auth.uid()));

drop policy if exists "channels_read_members" on public.channels;
create policy "channels_read_members" on public.channels for select to authenticated using (exists(select 1 from public.server_members m where m.server_id=server_id and m.user_id=auth.uid()));
drop policy if exists "channels_create_owner" on public.channels;
create policy "channels_create_owner" on public.channels for insert to authenticated with check (exists(select 1 from public.servers s where s.id=server_id and s.owner_id=auth.uid()));

drop policy if exists "channel_messages_members" on public.channel_messages;
create policy "channel_messages_members" on public.channel_messages for select to authenticated using (exists(select 1 from public.server_members m where m.server_id=(select server_id from public.channels c where c.id=channel_id) and m.user_id=auth.uid()));
drop policy if exists "channel_messages_insert_members" on public.channel_messages;
create policy "channel_messages_insert_members" on public.channel_messages for insert to authenticated with check (
  sender_id=auth.uid() and exists(select 1 from public.server_members m where m.server_id=(select server_id from public.channels c where c.id=channel_id) and m.user_id=auth.uid())
);

-- Realtime
do $$
begin
  alter publication supabase_realtime add table public.channel_messages;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.dm_messages;
exception when duplicate_object then null;
end $$;
