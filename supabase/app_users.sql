-- Custom app users (JWT auth + Resend emails — same pattern as ineedcarbonbuckets)
-- Run after used_listings.sql or on a fresh project before listings.

create table if not exists public.app_users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  password_hash text not null,
  first_name text,
  last_name text,
  email_verified boolean not null default false,
  verification_token text,
  reset_token text,
  reset_token_expiry timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists app_users_email_idx on public.app_users (lower(email));

-- Point listing owner_id at app_users instead of auth.users
alter table public.used_listings
  drop constraint if exists used_listings_owner_id_fkey;

alter table public.listing_payments
  drop constraint if exists listing_payments_owner_id_fkey;

alter table public.used_listings
  add constraint used_listings_owner_id_fkey
  foreign key (owner_id) references public.app_users(id) on delete cascade;

alter table public.listing_payments
  add constraint listing_payments_owner_id_fkey
  foreign key (owner_id) references public.app_users(id) on delete set null;

-- RLS: backend uses service role; public read of published listings unchanged.
alter table public.app_users enable row level security;

drop policy if exists "app_users_no_client_access" on public.app_users;
create policy "app_users_no_client_access"
on public.app_users
for all
to anon, authenticated
using (false)
with check (false);
