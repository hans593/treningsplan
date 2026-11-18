-- Hele app-tilstanden per bruker (plan, økter, målinger). Brukes til gjenoppretting på ny telefon.
create table public.app_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null,
  app_version text,
  updated_at timestamptz not null default now()
);

-- Økter i lesbar form (planlagte og ekstra), for oversikt og analyse.
create table public.okter (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  dato date not null,
  type text not null,
  tittel text not null,
  minutter int not null,
  anstrengelse text not null,
  status text not null,
  ekstra boolean not null default false,
  handtert text,
  notat text,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
create index okter_user_dato on public.okter (user_id, dato);

-- Vekt og midjemål.
create table public.malinger (
  user_id uuid not null references auth.users(id) on delete cascade,
  dato date not null,
  vekt_kg numeric(5,1),
  midje_cm numeric(5,1),
  updated_at timestamptz not null default now(),
  primary key (user_id, dato)
);

alter table public.app_state enable row level security;
alter table public.okter enable row level security;
alter table public.malinger enable row level security;

create policy "egne data" on public.app_state for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "egne data" on public.okter for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "egne data" on public.malinger for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
