create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  phone text not null,
  birth_date date,
  gender text check (gender in ('male', 'female')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  appointment_date date not null,
  appointment_time time not null,
  service text not null,
  doctor_name text,
  status text not null default 'scheduled' check (status in ('scheduled', 'completed', 'cancelled', 'no_show')),
  notes text,
  day_before_reminder_sent boolean not null default false,
  hour_before_reminder_sent boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists clients_user_id_idx on public.clients(user_id);
create index if not exists clients_phone_idx on public.clients(phone);
create index if not exists appointments_user_id_idx on public.appointments(user_id);
create index if not exists appointments_date_idx on public.appointments(appointment_date);
create index if not exists appointments_client_id_idx on public.appointments(client_id);
create index if not exists appointments_reminder_lookup_idx
  on public.appointments(appointment_date, status, day_before_reminder_sent, hour_before_reminder_sent);

alter table public.appointments
  drop constraint if exists appointments_client_owner_fk;

alter table public.appointments
  add constraint appointments_client_owner_fk
  foreign key (client_id, user_id)
  references public.clients(id, user_id)
  on delete cascade;

drop trigger if exists clients_set_updated_at on public.clients;
create trigger clients_set_updated_at
before update on public.clients
for each row execute function public.set_updated_at();

drop trigger if exists appointments_set_updated_at on public.appointments;
create trigger appointments_set_updated_at
before update on public.appointments
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.appointments enable row level security;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.clients to authenticated;
grant select, insert, update, delete on public.appointments to authenticated;

drop policy if exists "Users can select own profile" on public.profiles;
create policy "Users can select own profile"
on public.profiles for select
using (id = auth.uid());

drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can insert own profile"
on public.profiles for insert
with check (id = auth.uid());

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles for update
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists "Users can select own clients" on public.clients;
create policy "Users can select own clients"
on public.clients for select
using (user_id = auth.uid());

drop policy if exists "Users can insert own clients" on public.clients;
create policy "Users can insert own clients"
on public.clients for insert
with check (user_id = auth.uid());

drop policy if exists "Users can update own clients" on public.clients;
create policy "Users can update own clients"
on public.clients for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users can delete own clients" on public.clients;
create policy "Users can delete own clients"
on public.clients for delete
using (user_id = auth.uid());

drop policy if exists "Users can select own appointments" on public.appointments;
create policy "Users can select own appointments"
on public.appointments for select
using (user_id = auth.uid());

drop policy if exists "Users can insert own appointments" on public.appointments;
create policy "Users can insert own appointments"
on public.appointments for insert
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.clients
    where clients.id = appointments.client_id
      and clients.user_id = auth.uid()
  )
);

drop policy if exists "Users can update own appointments" on public.appointments;
create policy "Users can update own appointments"
on public.appointments for update
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.clients
    where clients.id = appointments.client_id
      and clients.user_id = auth.uid()
  )
);

drop policy if exists "Users can delete own appointments" on public.appointments;
create policy "Users can delete own appointments"
on public.appointments for delete
using (user_id = auth.uid());
