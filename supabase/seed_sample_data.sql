-- Optional development seed data.
-- Replace this value with an existing auth.users.id from your Supabase project before running.
-- Example:
--   select id, email from auth.users;

do $$
declare
  demo_user_id uuid := '00000000-0000-0000-0000-000000000000';
  ivan_id uuid := gen_random_uuid();
  aziza_id uuid := gen_random_uuid();
  dilshod_id uuid := gen_random_uuid();
  madina_id uuid := gen_random_uuid();
  bekzod_id uuid := gen_random_uuid();
begin
  if demo_user_id = '00000000-0000-0000-0000-000000000000' then
    raise exception 'Set demo_user_id to a real auth.users.id before running this seed.';
  end if;

  insert into public.clients (id, user_id, first_name, last_name, phone, birth_date, gender, notes)
  values
    (ivan_id, demo_user_id, 'Иван', 'Иванов', '+998 90 123 45 67', '1990-05-12', 'male', 'Предпочитает утренние записи.'),
    (aziza_id, demo_user_id, 'Азиза', 'Каримова', '+998 91 234 56 78', '1995-11-03', 'female', null),
    (dilshod_id, demo_user_id, 'Дилшод', 'Ахмедов', '+998 93 345 67 89', '1987-02-20', 'male', null),
    (madina_id, demo_user_id, 'Мадина', 'Алиева', '+998 94 456 78 90', '1992-07-18', 'female', 'Чувствительность к холодному.'),
    (bekzod_id, demo_user_id, 'Бекзод', 'Рахимов', '+998 97 567 89 01', null, 'male', null);

  insert into public.appointments (user_id, client_id, appointment_date, appointment_time, service, doctor_name, status, notes)
  values
    (demo_user_id, ivan_id, current_date, '10:00', 'Лечение кариеса', 'Доктор Саидов', 'scheduled', null),
    (demo_user_id, aziza_id, current_date, '12:30', 'Чистка зубов', 'Доктор Саидов', 'completed', null),
    (demo_user_id, dilshod_id, current_date + 1, '14:30', 'Консультация', 'Доктор Ниязова', 'scheduled', 'Проверить снимок.'),
    (demo_user_id, madina_id, current_date + 1, '16:00', 'Отбеливание', null, 'scheduled', null),
    (demo_user_id, bekzod_id, current_date + 2, '09:30', 'Удаление зуба', 'Доктор Саидов', 'scheduled', null),
    (demo_user_id, ivan_id, current_date - 7, '11:00', 'Чистка зубов', 'Доктор Ниязова', 'completed', null),
    (demo_user_id, aziza_id, current_date - 5, '15:00', 'Лечение кариеса', 'Доктор Саидов', 'cancelled', null),
    (demo_user_id, dilshod_id, current_date + 5, '13:00', 'Имплантация', 'Доктор Ниязова', 'scheduled', null),
    (demo_user_id, madina_id, current_date + 8, '17:30', 'Консультация', null, 'scheduled', null),
    (demo_user_id, bekzod_id, current_date - 12, '10:30', 'Лечение кариеса', 'Доктор Саидов', 'no_show', null);
end $$;
