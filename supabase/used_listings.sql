-- Supabase schema for paid used downpipe listings
-- Run in Supabase SQL editor (or via migrations if you use Supabase CLI).

-- Extensions
create extension if not exists pgcrypto;

-- Tables
create table if not exists public.used_listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'draft' check (status in ('draft','published','sold','archived')),
  title text not null,
  price_cents int not null check (price_cents >= 0),
  currency text not null default 'USD',
  condition text,
  chassis text[] not null default '{}'::text[],
  engine text[] not null default '{}'::text[],
  notes text,
  location text,
  contact_email text,
  images text[] not null default '{}'::text[],
  created_at timestamptz not null default now(),
  published_at timestamptz
);

create index if not exists used_listings_status_idx on public.used_listings(status);
create index if not exists used_listings_owner_idx on public.used_listings(owner_id);

create table if not exists public.listing_payments (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.used_listings(id) on delete set null,
  owner_id uuid references auth.users(id) on delete set null,
  stripe_checkout_session_id text unique,
  stripe_payment_intent_id text,
  amount_cents int,
  currency text,
  status text not null default 'created' check (status in ('created','paid','failed','refunded')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create index if not exists listing_payments_listing_idx on public.listing_payments(listing_id);

-- Row Level Security
alter table public.used_listings enable row level security;
alter table public.listing_payments enable row level security;

-- Public can read published listings
drop policy if exists "used_listings_public_select_published" on public.used_listings;
create policy "used_listings_public_select_published"
on public.used_listings
for select
to anon, authenticated
using (status = 'published');

-- Owners can manage their listings
drop policy if exists "used_listings_owner_insert" on public.used_listings;
create policy "used_listings_owner_insert"
on public.used_listings
for insert
to authenticated
with check (owner_id = auth.uid());

drop policy if exists "used_listings_owner_update" on public.used_listings;
create policy "used_listings_owner_update"
on public.used_listings
for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "used_listings_owner_delete" on public.used_listings;
create policy "used_listings_owner_delete"
on public.used_listings
for delete
to authenticated
using (owner_id = auth.uid());

-- Payments: owner can read their own payment rows
drop policy if exists "listing_payments_owner_select" on public.listing_payments;
create policy "listing_payments_owner_select"
on public.listing_payments
for select
to authenticated
using (owner_id = auth.uid());

-- Payments: owner can insert a placeholder row (server can also insert using service role)
drop policy if exists "listing_payments_owner_insert" on public.listing_payments;
create policy "listing_payments_owner_insert"
on public.listing_payments
for insert
to authenticated
with check (owner_id = auth.uid());

-- Payments: no direct updates from clients (webhook uses service role, bypassing RLS)
drop policy if exists "listing_payments_no_client_update" on public.listing_payments;
create policy "listing_payments_no_client_update"
on public.listing_payments
for update
to authenticated
using (false)
with check (false);

-- Storage (manual steps):
-- 1) Create a storage bucket named: used-listings (public)
-- 2) Add policies so only owners can upload/delete their own paths, e.g. prefix with user id.

