-- Two SMS reminders per appointment:
--   1. day_before: same clock time, 24 hours before the visit
--   2. hour_before: 60 minutes before the visit
--
-- Safe to run on projects that already have reminder_sent, and on fresh
-- installs whose initial schema already has the two new columns.

alter table public.appointments
  add column if not exists day_before_reminder_sent boolean not null default false;

alter table public.appointments
  add column if not exists hour_before_reminder_sent boolean not null default false;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'appointments'
      and column_name = 'reminder_sent'
  ) then
    update public.appointments
    set day_before_reminder_sent = reminder_sent
    where reminder_sent is true;

    alter table public.appointments drop column reminder_sent;
  end if;
end $$;

drop index if exists public.appointments_reminder_sent_idx;
drop index if exists public.appointments_reminder_lookup_idx;

create index if not exists appointments_reminder_lookup_idx
  on public.appointments (appointment_date, status, day_before_reminder_sent, hour_before_reminder_sent);
