import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ReminderKind = "day_before" | "hour_before";

type AppointmentRow = {
  id: string;
  appointment_date: string;
  appointment_time: string;
  service: string;
  day_before_reminder_sent: boolean;
  hour_before_reminder_sent: boolean;
  clients: {
    first_name: string;
    last_name: string;
    phone: string;
  } | null;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const eskizEmail = Deno.env.get("ESKIZ_EMAIL") ?? "";
const eskizPassword = Deno.env.get("ESKIZ_PASSWORD") ?? "";
const eskizFrom = Deno.env.get("ESKIZ_FROM") ?? "4546";
const clinicTimeZone = Deno.env.get("CLINIC_TIMEZONE") ?? "Asia/Tashkent";

const DAY_BEFORE_WINDOW_MS = 60 * 60 * 1000;
const HOUR_BEFORE_OFFSET_MS = 60 * 60 * 1000;
const DAY_BEFORE_OFFSET_MS = 24 * 60 * 60 * 1000;

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    persistSession: false,
  },
});

Deno.serve(async () => {
  if (!supabaseUrl || !serviceRoleKey || !eskizEmail || !eskizPassword) {
    return json({ error: "Missing required environment variables." }, 500);
  }

  const now = new Date();
  const today = ymdInTimeZone(now, clinicTimeZone);
  const tomorrow = addCalendarDays(today, 1);

  const { data: appointments, error } = await supabase
    .from("appointments")
    .select(
      "id, appointment_date, appointment_time, service, day_before_reminder_sent, hour_before_reminder_sent, clients(first_name, last_name, phone)",
    )
    .in("appointment_date", [today, tomorrow])
    .eq("status", "scheduled")
    .or("day_before_reminder_sent.eq.false,hour_before_reminder_sent.eq.false");

  if (error) {
    console.error("Failed to query appointments", error);
    return json({ error: "Failed to query appointments." }, 500);
  }

  const due: Array<{ appointment: AppointmentRow; kind: ReminderKind }> = [];
  for (const appointment of (appointments ?? []) as AppointmentRow[]) {
    const startsAt = clinicDateTime(appointment.appointment_date, appointment.appointment_time);
    if (Number.isNaN(startsAt.getTime())) {
      continue;
    }

    const dayBeforeAt = new Date(startsAt.getTime() - DAY_BEFORE_OFFSET_MS);
    const hourBeforeAt = new Date(startsAt.getTime() - HOUR_BEFORE_OFFSET_MS);

    if (
      !appointment.day_before_reminder_sent &&
      now.getTime() >= dayBeforeAt.getTime() &&
      now.getTime() < dayBeforeAt.getTime() + DAY_BEFORE_WINDOW_MS
    ) {
      due.push({ appointment, kind: "day_before" });
    }

    if (
      !appointment.hour_before_reminder_sent &&
      now.getTime() >= hourBeforeAt.getTime() &&
      now.getTime() < startsAt.getTime()
    ) {
      due.push({ appointment, kind: "hour_before" });
    }
  }

  if (due.length === 0) {
    return json({
      timezone: clinicTimeZone,
      now: now.toISOString(),
      date: today,
      checked: appointments?.length ?? 0,
      sent: 0,
      results: [],
    });
  }

  const token = await getEskizToken();
  const results: Array<{ appointmentId: string; kind: ReminderKind; sent: boolean; error?: string }> = [];

  for (const item of due) {
    const { appointment, kind } = item;
    if (!appointment.clients?.phone) {
      results.push({ appointmentId: appointment.id, kind, sent: false, error: "Client phone is missing." });
      continue;
    }

    const claimed = await claimAppointment(appointment.id, kind);
    if (!claimed) {
      results.push({ appointmentId: appointment.id, kind, sent: false, error: "Already claimed by another run." });
      continue;
    }

    try {
      await sendSMS(token, appointment.clients.phone, reminderText(appointment, kind));
      results.push({ appointmentId: appointment.id, kind, sent: true });
    } catch (sendError) {
      console.error("Eskiz send failed", appointment.id, kind, sendError);
      await releaseAppointment(appointment.id, kind);
      results.push({
        appointmentId: appointment.id,
        kind,
        sent: false,
        error: sendError instanceof Error ? sendError.message : "Unknown Eskiz error.",
      });
    }
  }

  return json({
    timezone: clinicTimeZone,
    now: now.toISOString(),
    date: today,
    checked: appointments?.length ?? 0,
    sent: results.filter((result) => result.sent).length,
    results,
  });
});

function reminderColumn(kind: ReminderKind): "day_before_reminder_sent" | "hour_before_reminder_sent" {
  return kind === "day_before" ? "day_before_reminder_sent" : "hour_before_reminder_sent";
}

async function claimAppointment(id: string, kind: ReminderKind): Promise<boolean> {
  const column = reminderColumn(kind);
  const { data, error } = await supabase
    .from("appointments")
    .update({ [column]: true })
    .eq("id", id)
    .eq(column, false)
    .select("id")
    .maybeSingle();

  if (error) {
    console.error("Failed to claim appointment", id, kind, error);
    return false;
  }

  return Boolean(data);
}

async function releaseAppointment(id: string, kind: ReminderKind): Promise<void> {
  const column = reminderColumn(kind);
  const { error } = await supabase
    .from("appointments")
    .update({ [column]: false })
    .eq("id", id);

  if (error) {
    console.error("Failed to release appointment after SMS failure", id, kind, error);
  }
}

async function getEskizToken(): Promise<string> {
  const response = await fetch("https://notify.eskiz.uz/api/auth/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email: eskizEmail,
      password: eskizPassword,
    }),
  });

  if (!response.ok) {
    throw new Error(`Eskiz auth failed: ${response.status}`);
  }

  const body = await response.json();
  const token = body?.data?.token;
  if (!token) {
    throw new Error("Eskiz auth response did not include a token.");
  }

  return token;
}

async function sendSMS(token: string, phone: string, message: string): Promise<void> {
  const response = await fetch("https://notify.eskiz.uz/api/message/sms/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      mobile_phone: normalizePhone(phone),
      message,
      from: eskizFrom,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Eskiz SMS failed: ${response.status} ${text}`);
  }
}

function reminderText(appointment: AppointmentRow, kind: ReminderKind): string {
  const date = formatRussianDate(appointment.appointment_date);
  const time = appointment.appointment_time.slice(0, 5);
  if (kind === "day_before") {
    return `Клиника: напоминаем, что завтра, ${date} в ${time}, вы записаны на приём. Услуга: ${appointment.service}. Пожалуйста, приходите вовремя.`;
  }
  return `Клиника: напоминаем, что через час, в ${time}, вы записаны на приём. Услуга: ${appointment.service}. Пожалуйста, приходите вовремя.`;
}

function formatRussianDate(value: string): string {
  return new Intl.DateTimeFormat("ru-RU", {
    day: "numeric",
    month: "long",
    timeZone: "UTC",
  }).format(new Date(`${value}T00:00:00Z`));
}

function normalizePhone(value: string): string {
  return value.replace(/[^\d]/g, "");
}

function clinicDateTime(date: string, time: string): Date {
  const normalizedTime = normalizeTime(time);
  const naiveUtc = new Date(`${date}T${normalizedTime}Z`);
  if (Number.isNaN(naiveUtc.getTime())) {
    return naiveUtc;
  }

  const firstOffset = timeZoneOffsetMs(naiveUtc, clinicTimeZone);
  let utc = new Date(naiveUtc.getTime() - firstOffset);
  const secondOffset = timeZoneOffsetMs(utc, clinicTimeZone);
  if (secondOffset !== firstOffset) {
    utc = new Date(naiveUtc.getTime() - secondOffset);
  }
  return utc;
}

function normalizeTime(time: string): string {
  const [hour = "00", minute = "00", second = "00"] = time.split(":");
  return `${hour.padStart(2, "0")}:${minute.padStart(2, "0")}:${second.padStart(2, "0")}`;
}

function ymdInTimeZone(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function addCalendarDays(ymd: string, days: number): string {
  const [year, month, day] = ymd.split("-").map(Number);
  const utc = new Date(Date.UTC(year, month - 1, day + days));
  return utc.toISOString().slice(0, 10);
}

function timeZoneOffsetMs(date: Date, timeZone: string): number {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone,
      hour12: false,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    }).formatToParts(date).map((part) => [part.type, part.value]),
  );

  let hour = Number(parts.hour);
  if (hour === 24) {
    hour = 0;
  }

  const asUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    hour,
    Number(parts.minute),
    Number(parts.second),
  );
  return asUtc - date.getTime();
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}
