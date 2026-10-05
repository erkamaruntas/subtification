-- Subtification backend rebuild / repair SQL.
-- Safe by default: it does NOT drop tables and does NOT delete rows.
-- Paste this whole file into Supabase SQL Editor and run it.

create extension if not exists pgcrypto;

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  amount numeric(12, 2) not null default 0,
  currency text not null default '₺',
  billing_cycle text not null default 'monthly',
  next_billing_date date not null default current_date,
  category text not null default 'other',
  emoji text not null default 'apps',
  color text not null default '#0b7285',
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table if exists public.subscriptions
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists name text,
  add column if not exists amount numeric(12, 2) default 0,
  add column if not exists currency text default '₺',
  add column if not exists billing_cycle text default 'monthly',
  add column if not exists next_billing_date date default current_date,
  add column if not exists category text default 'other',
  add column if not exists emoji text default 'apps',
  add column if not exists color text default '#0b7285',
  add column if not exists notes text,
  add column if not exists is_active boolean default true,
  add column if not exists duration_months integer,
  add column if not exists is_installment boolean not null default false,
  add column if not exists first_billing_date date,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

-- Eski şemayla oluşturulmuş tablolarda user_id kısıtı cascade değildi; hesap silme
-- aboneliği olan kullanıcıda foreign key hatası veriyordu. Her çalıştırmada cascade yap.
alter table public.subscriptions
  drop constraint if exists subscriptions_user_id_fkey;

alter table public.subscriptions
  add constraint subscriptions_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

-- If an older table used `price`, copy it into `amount`.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscriptions'
      and column_name = 'price'
  ) then
    execute
      'update public.subscriptions set amount = price where amount is null or amount = 0';
  end if;
end $$;

update public.subscriptions
set
  currency = coalesce(currency, '₺'),
  billing_cycle = coalesce(billing_cycle, 'monthly'),
  next_billing_date = coalesce(next_billing_date, current_date),
  category = coalesce(category, 'other'),
  emoji = coalesce(emoji, 'apps'),
  color = coalesce(color, '#0b7285'),
  is_active = coalesce(is_active, true),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now());

-- Remove old category/billing constraints before installing the current app constraints.
do $$
declare
  constraint_record record;
begin
  for constraint_record in
    select conname
    from pg_constraint
    where conrelid = 'public.subscriptions'::regclass
      and contype = 'c'
      and (
        pg_get_constraintdef(oid) ilike '%category%'
        or pg_get_constraintdef(oid) ilike '%billing_cycle%'
      )
  loop
    execute format(
      'alter table public.subscriptions drop constraint if exists %I',
      constraint_record.conname
    );
  end loop;
end $$;

alter table public.subscriptions
  alter column amount set not null,
  alter column currency set not null,
  alter column billing_cycle set not null,
  alter column next_billing_date set not null,
  alter column category set not null,
  alter column emoji set not null,
  alter column color set not null,
  alter column is_active set not null,
  alter column created_at set not null,
  alter column updated_at set not null;

alter table public.subscriptions
  add constraint subscriptions_billing_cycle_check
  check (billing_cycle in ('monthly', 'yearly', 'weekly', 'quarterly'));

alter table public.subscriptions
  add constraint subscriptions_category_check
  check (
    category in (
      'entertainment',
      'music',
      'gaming',
      'news',
      'finance',
      'utilities',
      'shopping',
      'productivity',
      'cloud',
      'developer',
      'design',
      'health',
      'fitness',
      'food',
      'travel',
      'education',
      'social',
      'security',
      'other'
    )
  );

create index if not exists subscriptions_user_date_idx
  on public.subscriptions(user_id, next_billing_date);

create or replace function public.update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists subscriptions_updated_at
  on public.subscriptions;

create trigger subscriptions_updated_at
  before update on public.subscriptions
  for each row execute function public.update_updated_at();

alter table public.subscriptions enable row level security;

drop policy if exists "Users can manage their own subscriptions"
  on public.subscriptions;

create policy "Users can manage their own subscriptions"
  on public.subscriptions
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

notify pgrst, 'reload schema';
