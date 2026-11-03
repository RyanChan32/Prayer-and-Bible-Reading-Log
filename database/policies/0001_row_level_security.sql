-- One Day Closer: who can see and change what.
-- Run after database/migrations/0001_schema.sql.
--
-- Signed-out visitors can't reach any table. Group changes that involve
-- roles or membership go through the functions below, so the rules can't be
-- skipped by calling the database directly.

alter table public.profiles        enable row level security;
alter table public.prayers         enable row level security;
alter table public.readings        enable row level security;
alter table public.groups          enable row level security;
alter table public.group_members   enable row level security;
alter table public.messages        enable row level security;
alter table public.message_praying enable row level security;

revoke all on all tables in schema public from public, anon, authenticated;
grant select, update (display_name)                 on public.profiles        to authenticated;
grant select, insert, update, delete                on public.prayers         to authenticated;
grant select, insert, update, delete                on public.readings        to authenticated;
grant select, update (name, description), delete    on public.groups          to authenticated;
grant select                                        on public.group_members   to authenticated;
grant select, insert                                on public.messages        to authenticated;
grant select, insert, delete                        on public.message_praying to authenticated;

-- The signed-in user's role in a group, or null if they aren't a member.
create function public.group_role(p_group uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.group_members
  where group_id = p_group and user_id = (select auth.uid());
$$;

-- Names are visible to signed-in users so the Community feed and groups can
-- show them. Emails are not stored here.
create policy "profiles: signed-in users can read" on public.profiles
  for select to authenticated using (true);
create policy "profiles: edit your own" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "prayers: read your own or public" on public.prayers
  for select to authenticated using (user_id = (select auth.uid()) or is_public);
create policy "prayers: add your own" on public.prayers
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "prayers: edit your own" on public.prayers
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "prayers: delete your own" on public.prayers
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "readings: read your own or public" on public.readings
  for select to authenticated using (user_id = (select auth.uid()) or is_public);
create policy "readings: add your own" on public.readings
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "readings: edit your own" on public.readings
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "readings: delete your own" on public.readings
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "groups: members can read" on public.groups
  for select to authenticated using (public.group_role(id) is not null);
create policy "groups: owners and admins can edit details" on public.groups
  for update to authenticated
  using (public.group_role(id) in ('owner', 'admin'))
  with check (public.group_role(id) in ('owner', 'admin'));
create policy "groups: owners can delete" on public.groups
  for delete to authenticated using (public.group_role(id) = 'owner');

create policy "group_members: members can read" on public.group_members
  for select to authenticated using (public.group_role(group_id) is not null);

create policy "messages: members can read" on public.messages
  for select to authenticated using (public.group_role(group_id) is not null);
create policy "messages: members can post" on public.messages
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (
      (type = 'text' and public.group_role(group_id) is not null)
      or (
        type = 'prayer'
        and (
          public.group_role(group_id) in ('owner', 'admin')
          or (
            public.group_role(group_id) = 'member'
            and (select g.members_can_share from public.groups g where g.id = group_id)
          )
        )
      )
    )
  );

create policy "message_praying: members can read" on public.message_praying
  for select to authenticated
  using (exists (
    select 1 from public.messages m
    where m.id = message_id and public.group_role(m.group_id) is not null
  ));
create policy "message_praying: react as yourself" on public.message_praying
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.messages m
      where m.id = message_id and m.type = 'prayer' and public.group_role(m.group_id) is not null
    )
  );
create policy "message_praying: remove your own" on public.message_praying
  for delete to authenticated using (user_id = (select auth.uid()));

create function public.create_group(p_name text, p_description text default '')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_group uuid;
begin
  if v_me is null then raise exception 'not_signed_in'; end if;
  insert into public.groups (name, description, owner_id)
  values (trim(p_name), trim(p_description), v_me)
  returning id into v_group;
  insert into public.group_members (group_id, user_id, role) values (v_group, v_me, 'owner');
  insert into public.messages (group_id, user_id, type, text)
  select v_group, v_me, 'system', p.display_name || ' created the group'
  from public.profiles p where p.id = v_me;
  return v_group;
end;
$$;

-- Returns the added person's display name.
create function public.add_group_member(p_group uuid, p_email text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_role text := public.group_role(p_group);
  v_can_invite boolean;
  v_user uuid;
  v_name text;
begin
  select members_can_invite into v_can_invite from public.groups where id = p_group;
  if not (v_role in ('owner', 'admin') or (v_role = 'member' and v_can_invite)) or v_role is null then
    raise exception 'not_allowed';
  end if;
  select u.id into v_user from auth.users u where lower(u.email) = lower(trim(p_email));
  if v_user is null then raise exception 'no_account'; end if;
  if exists (select 1 from public.group_members where group_id = p_group and user_id = v_user) then
    raise exception 'already_member';
  end if;
  insert into public.group_members (group_id, user_id, role) values (p_group, v_user, 'member');
  select display_name into v_name from public.profiles where id = v_user;
  insert into public.messages (group_id, user_id, type, text)
  select p_group, v_me, 'system', p.display_name || ' added ' || v_name
  from public.profiles p where p.id = v_me;
  return v_name;
end;
$$;

-- Covers both leaving a group (p_user is you) and removing someone else.
create function public.remove_group_member(p_group uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_role text := public.group_role(p_group);
  v_target_role text;
  v_my_name text;
  v_target_name text;
begin
  if v_role is null then raise exception 'not_allowed'; end if;
  select role into v_target_role from public.group_members where group_id = p_group and user_id = p_user;
  if v_target_role is null then raise exception 'not_a_member'; end if;
  if v_target_role = 'owner' then raise exception 'owner_must_transfer'; end if;
  if p_user <> v_me and not (v_role = 'owner' or (v_role = 'admin' and v_target_role = 'member')) then
    raise exception 'not_allowed';
  end if;
  delete from public.group_members where group_id = p_group and user_id = p_user;
  select display_name into v_my_name from public.profiles where id = v_me;
  select display_name into v_target_name from public.profiles where id = p_user;
  insert into public.messages (group_id, user_id, type, text)
  values (
    p_group, v_me, 'system',
    case when p_user = v_me then v_my_name || ' left the group'
         else v_my_name || ' removed ' || v_target_name end
  );
end;
$$;

create function public.set_member_role(p_group uuid, p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if public.group_role(p_group) is distinct from 'owner' then raise exception 'not_allowed'; end if;
  if p_role not in ('admin', 'member') then raise exception 'invalid_role'; end if;
  update public.group_members set role = p_role
  where group_id = p_group and user_id = p_user and role <> 'owner';
  if not found then raise exception 'not_a_member'; end if;
  select display_name into v_name from public.profiles where id = p_user;
  insert into public.messages (group_id, user_id, type, text)
  values (p_group, auth.uid(), 'system',
          v_name || ' is now ' || case when p_role = 'admin' then 'an admin' else 'a member' end);
end;
$$;

create function public.transfer_group_ownership(p_group uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_my_name text;
  v_target_name text;
begin
  if public.group_role(p_group) is distinct from 'owner' then raise exception 'not_allowed'; end if;
  if p_user = v_me then raise exception 'already_owner'; end if;
  if not exists (select 1 from public.group_members where group_id = p_group and user_id = p_user) then
    raise exception 'not_a_member';
  end if;
  update public.group_members set role = 'admin' where group_id = p_group and user_id = v_me;
  update public.group_members set role = 'owner' where group_id = p_group and user_id = p_user;
  update public.groups set owner_id = p_user where id = p_group;
  select display_name into v_my_name from public.profiles where id = v_me;
  select display_name into v_target_name from public.profiles where id = p_user;
  insert into public.messages (group_id, user_id, type, text)
  values (p_group, v_me, 'system', v_my_name || ' made ' || v_target_name || ' the owner');
end;
$$;

create function public.set_group_settings(p_group uuid, p_members_can_invite boolean, p_members_can_share boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.group_role(p_group) is distinct from 'owner' then raise exception 'not_allowed'; end if;
  update public.groups
  set members_can_invite = p_members_can_invite, members_can_share = p_members_can_share
  where id = p_group;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.group_role(uuid) from public, anon;
revoke all on function public.create_group(text, text) from public, anon;
revoke all on function public.add_group_member(uuid, text) from public, anon;
revoke all on function public.remove_group_member(uuid, uuid) from public, anon;
revoke all on function public.set_member_role(uuid, uuid, text) from public, anon;
revoke all on function public.transfer_group_ownership(uuid, uuid) from public, anon;
revoke all on function public.set_group_settings(uuid, boolean, boolean) from public, anon;

grant execute on function public.group_role(uuid) to authenticated;
grant execute on function public.create_group(text, text) to authenticated;
grant execute on function public.add_group_member(uuid, text) to authenticated;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated;
grant execute on function public.set_group_settings(uuid, boolean, boolean) to authenticated;
