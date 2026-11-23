create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text unique,
  auth_phone text,
  id_card_number text,
  full_name text not null,
  contact_number text,
  island text,
  permanent_address text,
  role text not null default 'user',
  created_at timestamptz not null default now(),
  admin_approved_at timestamptz,
  admin_rejected_at timestamptz
);

alter table public.profiles
  drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('user', 'admin', 'editor', 'content_writer'));

drop policy if exists "profiles_owner_or_admin_requests_read" on public.profiles;
drop policy if exists "profiles_owner_or_admin_read" on public.profiles;
drop index if exists public.profiles_pending_admin_requests_idx;
alter table public.profiles
  drop column if exists admin_requested;

alter table public.profiles
  add column if not exists id_card_number text;
alter table public.profiles
  add column if not exists auth_phone text;
alter table public.profiles
  alter column email drop not null;

alter table public.profiles
  drop constraint if exists profiles_id_card_number_format;

update public.profiles
  set id_card_number = upper(regexp_replace(id_card_number, '^A-', 'A', 'i'))
  where id_card_number ~* '^A-';

alter table public.profiles
  add constraint profiles_id_card_number_format
  check (id_card_number is null or id_card_number ~* '^A[A-Z0-9][A-Z0-9-]*$');

alter table public.profiles
  drop constraint if exists profiles_auth_phone_format;
alter table public.profiles
  add constraint profiles_auth_phone_format
  check (auth_phone is null or auth_phone ~ '^\+[1-9][0-9]{7,14}$');

create unique index if not exists profiles_id_card_number_unique
  on public.profiles (upper(id_card_number))
  where id_card_number is not null;

create index if not exists profiles_id_card_number_lookup_idx
  on public.profiles (id_card_number)
  where id_card_number is not null;

create unique index if not exists profiles_auth_phone_unique
  on public.profiles (auth_phone)
  where auth_phone is not null;

create table if not exists public.admin_bootstrap (
  singleton boolean primary key default true check (singleton),
  email text not null,
  claimed boolean not null default false
);

insert into public.admin_bootstrap (singleton, email, claimed)
values (true, 'xoaxjillsender@gmail.com', false)
on conflict (singleton) do update
set email = excluded.email
where public.admin_bootstrap.claimed = false;

alter table public.profiles enable row level security;
alter table public.admin_bootstrap enable row level security;

revoke all on table public.admin_bootstrap from anon, authenticated;
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create or replace function public.can_manage_family_tree()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role in ('admin', 'editor')
  );
$$;

revoke all on function public.can_manage_family_tree() from public;
grant execute on function public.can_manage_family_tree() to authenticated;

create or replace function public.can_submit_family_record()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role in ('user', 'admin', 'editor')
  );
$$;

revoke all on function public.can_submit_family_record() from public;
grant execute on function public.can_submit_family_record() to authenticated;

create or replace function public.can_publish_news()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role in ('admin', 'content_writer')
  );
$$;

revoke all on function public.can_publish_news() from public;
grant execute on function public.can_publish_news() to authenticated;

create policy "profiles_owner_or_admin_read"
on public.profiles
for select
to authenticated
using (
  id = (select auth.uid())
  or public.is_admin()
);

insert into public.profiles (
  id, email, auth_phone, id_card_number, full_name, contact_number, island, permanent_address, role
)
select
  u.id,
  nullif(lower(u.email), ''),
  case when nullif(u.email, '') is null then nullif(u.phone, '') end,
  upper(regexp_replace(nullif(trim(u.raw_user_meta_data ->> 'id_card_number'), ''), '^A-', 'A', 'i')),
  coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''), split_part(coalesce(nullif(u.email, ''), nullif(u.phone, ''), ''), '@', 1)),
  u.raw_user_meta_data ->> 'contact_number',
  u.raw_user_meta_data ->> 'island',
  u.raw_user_meta_data ->> 'permanent_address',
  'user'
from auth.users as u
where nullif(u.email, '') is not null or nullif(u.phone, '') is not null
on conflict (id) do nothing;

do $$
declare
  bootstrap_email text;
  bootstrap_claimed boolean;
begin
  select email, claimed
    into bootstrap_email, bootstrap_claimed
    from public.admin_bootstrap
    where singleton = true
    for update;

  if not bootstrap_claimed then
    update public.profiles
      set role = 'admin',
          admin_approved_at = now()
      where lower(email) = lower(bootstrap_email);

    if found then
      update public.admin_bootstrap set claimed = true where singleton = true;
    end if;
  end if;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  bootstrap_email text;
  bootstrap_claimed boolean;
  assigned_role text := 'user';
begin
  select email, claimed
    into bootstrap_email, bootstrap_claimed
    from public.admin_bootstrap
    where singleton = true
    for update;

  if not bootstrap_claimed and lower(new.email) = lower(bootstrap_email) then
    assigned_role := 'admin';
    update public.admin_bootstrap set claimed = true where singleton = true;
  end if;

  insert into public.profiles (
    id, email, auth_phone, id_card_number, full_name, contact_number, island, permanent_address, role
  )
  values (
    new.id,
    nullif(lower(new.email), ''),
    nullif(new.phone, ''),
    upper(regexp_replace(nullif(trim(new.raw_user_meta_data ->> 'id_card_number'), ''), '^A-', 'A', 'i')),
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(coalesce(nullif(new.email, ''), nullif(new.phone, ''), ''), '@', 1)),
    new.raw_user_meta_data ->> 'contact_number',
    new.raw_user_meta_data ->> 'island',
    new.raw_user_meta_data ->> 'permanent_address',
    assigned_role
  )
  on conflict (id) do nothing;

  update auth.users
    set raw_user_meta_data = new.raw_user_meta_data - 'id_card_number'
    where id = new.id
      and new.raw_user_meta_data ? 'id_card_number';

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;

drop function if exists public.approve_admin_request(uuid);
drop function if exists public.reject_admin_request(uuid);

create or replace function public.set_user_role(target_user_id uuid, new_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_role text;
begin
  if new_role is null or new_role not in ('user', 'admin', 'editor', 'content_writer') then
    raise exception 'Role must be user, admin, editor, or content_writer';
  end if;

  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(208144, 1);

  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  if target_user_id = (select auth.uid()) then
    raise exception 'You cannot change your own role';
  end if;

  select role
    into existing_role
    from public.profiles
    where id = target_user_id
    for update;

  if not found then
    raise exception 'User account not found';
  end if;

  if existing_role = 'admin' and new_role <> 'admin'
     and (select count(*) from public.profiles where role = 'admin') <= 1 then
    raise exception 'The last administrator cannot be demoted';
  end if;

  update public.profiles
    set role = new_role
    where id = target_user_id;
end;
$$;

revoke all on function public.set_user_role(uuid, text) from public;
grant execute on function public.set_user_role(uuid, text) to authenticated;

create table if not exists public.family_members (
  id text primary key,
  member_data jsonb not null
    check (jsonb_typeof(member_data) = 'object' and member_data ->> 'id' = id),
  status text not null check (status in ('pending', 'verified')),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.family_members enable row level security;
revoke all on table public.family_members from anon, authenticated;
grant select (id, member_data, status, created_at, updated_at)
  on table public.family_members to anon, authenticated;
grant select (created_by) on table public.family_members to authenticated;
grant insert (id, member_data, status, created_by)
  on table public.family_members to authenticated;
grant insert (updated_at)
  on table public.family_members to authenticated;
grant update (id, member_data, status, created_by, updated_at)
  on table public.family_members to authenticated;
grant delete on table public.family_members to authenticated;

create index if not exists family_members_status_id_idx
  on public.family_members (status, id);
create index if not exists family_members_owner_pending_idx
  on public.family_members (created_by, created_at)
  where status = 'pending';

drop policy if exists "family_members_public_verified_read" on public.family_members;
create policy "family_members_public_verified_read"
on public.family_members
for select
to anon, authenticated
using (status = 'verified');

drop policy if exists "family_members_owner_pending_read" on public.family_members;
create policy "family_members_owner_pending_read"
on public.family_members
for select
to authenticated
using (status = 'pending' and created_by = (select auth.uid()));

drop policy if exists "family_members_admin_read" on public.family_members;
drop policy if exists "family_members_manager_read" on public.family_members;
create policy "family_members_manager_read"
on public.family_members
for select
to authenticated
using (public.can_manage_family_tree());

drop policy if exists "family_members_owner_pending_insert" on public.family_members;
create policy "family_members_owner_pending_insert"
on public.family_members
for insert
to authenticated
with check (
  public.can_submit_family_record()
  and
  created_by = (select auth.uid())
  and status = 'pending'
);

drop policy if exists "family_members_admin_insert" on public.family_members;
drop policy if exists "family_members_manager_insert" on public.family_members;
create policy "family_members_manager_insert"
on public.family_members
for insert
to authenticated
with check (public.can_manage_family_tree());

drop policy if exists "family_members_admin_update" on public.family_members;
drop policy if exists "family_members_manager_update" on public.family_members;
create policy "family_members_manager_update"
on public.family_members
for update
to authenticated
using (public.can_manage_family_tree())
with check (public.can_manage_family_tree());

drop policy if exists "family_members_admin_delete" on public.family_members;
drop policy if exists "family_members_manager_delete" on public.family_members;
create policy "family_members_manager_delete"
on public.family_members
for delete
to authenticated
using (public.can_manage_family_tree());

create table if not exists public.news_articles (
  id text primary key,
  category text not null check (category in ('council', 'community', 'development')),
  title_dv text not null,
  title_en text not null,
  published_at timestamptz not null default now(),
  summary_dv text not null,
  summary_en text not null,
  image text not null,
  created_by uuid not null references auth.users (id) on delete restrict
);
create index if not exists news_articles_published_at_idx
  on public.news_articles (published_at desc);

alter table public.news_articles enable row level security;
revoke all on table public.news_articles from anon, authenticated;
grant select (id, category, title_dv, title_en, published_at, summary_dv, summary_en, image)
  on table public.news_articles to anon, authenticated;
grant insert (id, category, title_dv, title_en, summary_dv, summary_en, image, created_by)
  on table public.news_articles to authenticated;
grant update (category, title_dv, title_en, summary_dv, summary_en, image)
  on table public.news_articles to authenticated;
grant delete on table public.news_articles to authenticated;

drop policy if exists "news_articles_public_read" on public.news_articles;
create policy "news_articles_public_read"
on public.news_articles
for select
to anon, authenticated
using (true);

drop policy if exists "news_articles_writer_insert" on public.news_articles;
create policy "news_articles_writer_insert"
on public.news_articles
for insert
to authenticated
with check (
  public.can_publish_news()
  and created_by = (select auth.uid())
);

drop policy if exists "news_articles_writer_update" on public.news_articles;
create policy "news_articles_writer_update"
on public.news_articles
for update
to authenticated
using (public.can_publish_news())
with check (public.can_publish_news());

drop policy if exists "news_articles_writer_delete" on public.news_articles;
create policy "news_articles_writer_delete"
on public.news_articles
for delete
to authenticated
using (public.can_publish_news());

notify pgrst, 'reload schema';
