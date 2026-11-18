-- Bekreft nye kontoer automatisk, så man kan logge inn med en gang etter registrering
-- (samme effekt som å slå av «Confirm email» i Supabase-innstillingene).
create or replace function public.auto_confirm_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end;
$$;

revoke execute on function public.auto_confirm_email() from public, anon, authenticated;

create trigger auto_confirm_email
  before insert on auth.users
  for each row execute function public.auto_confirm_email();
