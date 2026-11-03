-- One Day Closer: tables and account setup.
-- Run this first, then database/policies/0001_row_level_security.sql.

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  created_at   timestamptz not null default now()
);

create table public.prayers (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  text       text not null check (char_length(text) > 0),
  tags       text[] not null default '{}',
  is_public  boolean not null default false,
  answered   boolean not null default false,
  date       date not null default current_date,
  created_at timestamptz not null default now()
);
create index prayers_user_date_idx on public.prayers (user_id, date desc);
create index prayers_public_idx on public.prayers (created_at desc) where is_public;

create table public.readings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  date        date not null default current_date,
  book        text not null,
  chapter     integer not null check (chapter > 0),
  chapter_end integer check (chapter_end >= chapter),
  v_start     integer check (v_start > 0),
  v_end       integer check (v_end > 0),
  notes       text not null default '',
  tags        text[] not null default '{}',
  is_public   boolean not null default false,
  created_at  timestamptz not null default now()
);
create index readings_user_date_idx on public.readings (user_id, date desc);
create index readings_public_idx on public.readings (created_at desc) where is_public;

create table public.groups (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null check (char_length(name) > 0),
  description        text not null default '',
  owner_id           uuid not null references public.profiles (id) on delete cascade,
  members_can_invite boolean not null default false,
  members_can_share  boolean not null default true,
  created_at         timestamptz not null default now()
);

create table public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id);
create unique index group_members_one_owner_idx on public.group_members (group_id) where role = 'owner';

create table public.messages (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  type       text not null default 'text' check (type in ('text', 'prayer', 'system')),
  text       text,
  prayer     jsonb,
  created_at timestamptz not null default now()
);
create index messages_group_time_idx on public.messages (group_id, created_at);

create table public.message_praying (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  primary key (message_id, user_id)
);

-- Every new login account gets a profile automatically.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email, '@', 1)), 80)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
