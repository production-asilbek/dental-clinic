-- Schedule send-appointment-reminders every 5 minutes.
-- Run this in the Supabase SQL Editor after deploying the Edge Function.
-- Replace YOUR_PROJECT_REF and YOUR_SUPABASE_ANON_KEY.
--
-- pg_cron uses UTC. Every 5 minutes is timezone-independent.
-- The function itself interprets appointment times in Asia/Tashkent.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

select cron.unschedule(jobid)
from cron.job
where jobname = 'send-appointment-reminders';

select
  cron.schedule(
    'send-appointment-reminders',
    '*/5 * * * *',
    $$
    select
      net.http_post(
        url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-appointment-reminders',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', 'YOUR_SUPABASE_ANON_KEY'
        ),
        body := jsonb_build_object('source', 'pg_cron'),
        timeout_milliseconds := 60000
      ) as request_id;
    $$
  );
