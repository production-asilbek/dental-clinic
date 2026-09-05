# Клиника

SwiftUI iOS 17 MVP for internal dental clinic management in Uzbekistan.

The app includes Google login through Supabase Auth, client CRUD, appointment CRUD, a simple dashboard, appointment history, and a Supabase Edge Function that sends two Eskiz SMS reminders: one day before the visit at the same clock time, and again one hour before the appointment.

## Stack

- Swift + SwiftUI
- MVVM
- Supabase Auth and PostgreSQL
- Supabase Row Level Security
- Supabase Edge Functions
- Eskiz SMS API
- iOS 17+

No Firebase, no custom backend server, and no Eskiz credentials in the iOS app.

## Project Structure

```text
Clinic.xcodeproj
Clinic/
  ClinicApp.swift
  Models.swift
  Services.swift
  ViewModels.swift
  Views.swift
  Config/
    Shared.xcconfig
    Development.xcconfig.example
supabase/
  migrations/
    20260901190000_initial_schema.sql
    20260901200000_two_appointment_reminders.sql
  functions/
    send-appointment-reminders/
      index.ts
  cron_send_appointment_reminders.sql
  seed_sample_data.sql
```

## Step 1: Create Supabase Project

Create a new Supabase project at [supabase.com](https://supabase.com).

Copy:

- Project URL
- anon public key

Do not copy or store the service role key in the iOS project.

## Step 2: Run Database Migrations

Install the Supabase CLI, link your project, then run:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

The migration creates:

- `profiles`
- `clients`
- `appointments`
- indexes
- foreign keys
- update timestamp triggers
- RLS policies so users can only access their own data

Optional sample data is in `supabase/seed_sample_data.sql`. Replace `demo_user_id` with a real `auth.users.id` before running it.

## Step 3: Configure Google OAuth

In Supabase Dashboard:

1. Go to Authentication > Providers.
2. Enable Google.
3. Add your Google OAuth client id and secret.
4. Add the app redirect URL:

```text
uz.clinika.mvp://login-callback
```

If you change `PRODUCT_BUNDLE_IDENTIFIER`, update the redirect URL in Supabase as well.

## Step 4: iOS Supabase Environment Values

`Clinic/Config/Shared.xcconfig` is committed so the project builds immediately after cloning:

```text
SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY = YOUR_SUPABASE_ANON_KEY
```

The Supabase anon key is a public client key used by the iOS app. Do not put service role keys, Eskiz credentials, or other private secrets in any iOS config file.

## Step 5: Deploy Edge Function

Deploy:

```bash
supabase functions deploy send-appointment-reminders --no-verify-jwt
```

The function uses the service role key inside Supabase Functions runtime and must not be called from app code as a user feature.

Optional clinic timezone (defaults to `Asia/Tashkent`):

```bash
supabase secrets set CLINIC_TIMEZONE="Asia/Tashkent"
```

## Step 6: Configure Eskiz Credentials Securely

Set Edge Function secrets:

```bash
supabase secrets set ESKIZ_EMAIL="your-eskiz-email"
supabase secrets set ESKIZ_PASSWORD="your-eskiz-password"
supabase secrets set ESKIZ_FROM="4546"
```

Supabase automatically provides `SUPABASE_URL`. Also set the service role key if your project does not expose it to functions:

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
```

Never put `ESKIZ_EMAIL`, `ESKIZ_PASSWORD`, Eskiz tokens, or the Supabase service role key in Swift code.

## Step 7: Schedule Reminder Execution

The function must run **every 5 minutes**, not once a day. A daily job cannot hit the appointment clock time.

Each scheduled visit gets two SMS messages:

| Reminder | When it sends | Example (`14:30` visit on 3 Sep) |
| --- | --- | --- |
| Day before | Same clock time, 24 hours earlier | 2 Sep at `14:30` |
| Hour before | 60 minutes before the visit | 3 Sep at `13:30` |

The function:

1. Looks at today's and tomorrow's `scheduled` appointments in `Asia/Tashkent`.
2. Sends the day-before SMS if the current time is in the 1-hour window after that due time and `day_before_reminder_sent = false`.
3. Sends the hour-before SMS if the current time is between one hour before the visit and the visit start, and `hour_before_reminder_sent = false`.
4. Claims the matching flag first so two overlapping cron runs cannot send duplicates.
5. Sends Russian SMS text through Eskiz.
6. Keeps the flag `true` after success.
7. Reverts the flag to `false` and logs the error if Eskiz fails.

Late bookings skip the day-before SMS if that window already passed. The hour-before SMS still goes out.

### Option A: Supabase Dashboard Cron

1. Open [Supabase Dashboard](https://supabase.com/dashboard) → your project.
2. Go to **Integrations → Cron** (or **Database → Cron**).
3. Click **Create job**.
4. Name: `send-appointment-reminders`.
5. Schedule: `*/5 * * * *` (every 5 minutes, UTC).
6. Type: **Supabase Edge Function**.
7. Function: `send-appointment-reminders`.
8. HTTP method: `POST`.
9. Save the job.

If the form asks for headers, add:

```text
Content-Type: application/json
apikey: YOUR_SUPABASE_ANON_KEY
```

You can also pick **HTTP Request** and POST to:

```text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-appointment-reminders
```

### Option B: SQL cron job

Edit `supabase/cron_send_appointment_reminders.sql` with your project ref and anon key, then run it in **SQL Editor**.

Confirm the job exists:

```sql
select jobid, jobname, schedule, command
from cron.job
where jobname = 'send-appointment-reminders';
```

Recent runs:

```sql
select *
from cron.job_run_details
order by start_time desc
limit 20;
```

### Manual test

```bash
curl -X POST "https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-appointment-reminders" \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR_SUPABASE_ANON_KEY"
```

Create a visit for tomorrow at a time that is about 2–3 minutes from now to test the day-before SMS, or a visit today about 62 minutes from now to test the hour-before SMS. Then trigger the function (or wait for the next 5-minute cron tick) and check Eskiz plus the two reminder flags.

## Step 8: Run the iOS App

Open `Clinic.xcodeproj` in Xcode on macOS.

1. Let Swift Package Manager resolve `supabase-swift`.
2. Select an iPhone simulator or device.
3. Run the `Clinic` target.

## GitHub Actions Build

The repo includes `.github/workflows/ios-build.yml`.

The workflow:

1. Runs on GitHub's macOS runner.
2. Uses the committed `Clinic/Config/Shared.xcconfig`.
3. Resolves Swift Package Manager dependencies.
4. Builds the `Clinic` scheme for the iOS Simulator with signing disabled.

No GitHub secrets are required for the iOS simulator build. Do not add Eskiz credentials or the Supabase service role key to the iOS build workflow.

### CocoaPods

The app currently uses Swift Package Manager, so GitHub Actions does not run `pod install`.

`Podfile` is included only as a placeholder for future CocoaPods dependencies. If you add real pods later, open the generated `.xcworkspace` locally and update the GitHub Actions workflow to build the workspace instead of `Clinic.xcodeproj`.

## Manual Test Checklist

Test the complete MVP after configuring Supabase, Google OAuth, and Eskiz:

- Google Login
- Dashboard
- Create Client
- Edit Client
- Delete Client
- Create Appointment
- Edit Appointment
- Change appointment status
- View appointment history
- Create tomorrow's appointment
- Trigger `send-appointment-reminders`
- Verify Eskiz SMS delivery
- Verify `day_before_reminder_sent = true` after the day-before SMS
- Verify `hour_before_reminder_sent = true` after the hour-before SMS

Without real Supabase, Google OAuth, and Eskiz credentials, the login and SMS portions cannot be fully tested. The app intentionally does not include fake SMS behavior or private API credentials.
