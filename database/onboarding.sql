-- Per-user first-access tutorial. Existing profile ownership and role guards apply.
alter table public.profiles add column if not exists onboarding jsonb not null default '{}'::jsonb check(jsonb_typeof(onboarding)='object');
