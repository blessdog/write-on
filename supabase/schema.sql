-- Write On — Supabase Schema
-- Run this in the Supabase SQL Editor after creating the project.

-- ─── Profiles table (auto-created on signup via trigger) ────────────────────

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  email text,
  subscription text not null default 'free' check (subscription in ('free', 'pro', 'lifetime')),
  stripe_customer_id text,
  stripe_subscription_id text,
  subscription_expires_at timestamptz,
  monthly_minutes_limit integer not null default 15,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Users can read their own profile
create policy "Users read own profile"
  on public.profiles for select
  using (auth.uid() = id);

-- Users can update their own profile (limited fields)
create policy "Users update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Service role has full access (implicit via RLS bypass)

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Auto-update updated_at
create or replace function public.update_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.update_updated_at();

-- ─── Usage log table ────────────────────────────────────────────────────────

create table public.usage_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_seconds numeric(10, 2) not null default 0,
  session_bytes bigint not null default 0,
  month text not null, -- YYYY-MM format
  recorded_at timestamptz not null default now()
);

alter table public.usage_log enable row level security;

-- Users can read their own usage
create policy "Users read own usage"
  on public.usage_log for select
  using (auth.uid() = user_id);

-- Index for fast monthly aggregation
create index idx_usage_user_month on public.usage_log (user_id, month);

-- ─── Monthly usage view ─────────────────────────────────────────────────────

create or replace view public.monthly_usage as
select
  user_id,
  month,
  sum(session_seconds) as total_seconds,
  round(sum(session_seconds) / 60.0, 2) as total_minutes,
  sum(session_bytes) as total_bytes,
  count(*) as session_count
from public.usage_log
group by user_id, month;
