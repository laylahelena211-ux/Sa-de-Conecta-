-- SAÚDE CONECTA: estrutura inicial do banco Supabase
-- Execute todo este arquivo no SQL Editor do seu projeto Supabase.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  phone text,
  birth_date date,
  role text not null default 'patient' check (role in ('patient','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  address text not null,
  phone text,
  created_at timestamptz not null default now()
);
create table if not exists public.specialties (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);
create table if not exists public.professionals (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  specialty_id uuid references public.specialties(id) on delete set null,
  unit_id uuid references public.units(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles(id) on delete cascade,
  unit_id uuid not null references public.units(id),
  specialty_id uuid not null references public.specialties(id),
  professional_id uuid references public.professionals(id) on delete set null,
  appointment_date date not null,
  appointment_time time not null,
  note text,
  status text not null default 'Pendente' check (status in ('Pendente','Confirmada','Concluída','Cancelada')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, email, phone, birth_date)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name',''),
    coalesce(new.email,''),
    nullif(new.raw_user_meta_data ->> 'phone',''),
    nullif(new.raw_user_meta_data ->> 'birth_date','')::date
  ) on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Verifica a função administrativa sem expor privilégios ao navegador.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin');
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

alter table public.profiles enable row level security;
alter table public.units enable row level security;
alter table public.specialties enable row level security;
alter table public.professionals enable row level security;
alter table public.appointments enable row level security;
grant usage on schema public to authenticated;
revoke update on public.profiles from authenticated;
grant select, update (full_name, email, phone, birth_date) on public.profiles to authenticated;
grant select, insert, update, delete on public.units, public.specialties, public.professionals to authenticated;
grant select, insert, update on public.appointments to authenticated;

drop policy if exists "profiles_read_own_or_admin" on public.profiles;
create policy "profiles_read_own_or_admin" on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin" on public.profiles for update to authenticated
using (id = (select auth.uid()) or (select public.is_admin()))
with check (id = (select auth.uid()) or (select public.is_admin()));

-- Usuários autenticados podem consultar unidades, especialidades e profissionais.
drop policy if exists "units_read_authenticated" on public.units;
drop policy if exists "specialties_read_authenticated" on public.specialties;
drop policy if exists "professionals_read_authenticated" on public.professionals;
drop policy if exists "units_admin_all" on public.units;
drop policy if exists "specialties_admin_all" on public.specialties;
drop policy if exists "professionals_admin_all" on public.professionals;
create policy "units_read_authenticated" on public.units for select to authenticated using (true);
create policy "specialties_read_authenticated" on public.specialties for select to authenticated using (true);
create policy "professionals_read_authenticated" on public.professionals for select to authenticated using (true);
create policy "units_admin_all" on public.units for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "specialties_admin_all" on public.specialties for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "professionals_admin_all" on public.professionals for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "appointments_read_own_or_admin" on public.appointments;
drop policy if exists "appointments_create_own" on public.appointments;
drop policy if exists "appointments_update_own_pending_or_admin" on public.appointments;
create policy "appointments_read_own_or_admin" on public.appointments for select to authenticated
using (patient_id = (select auth.uid()) or (select public.is_admin()));
create policy "appointments_create_own" on public.appointments for insert to authenticated
with check (patient_id = (select auth.uid()) and status = 'Pendente');
create policy "appointments_update_own_pending_or_admin" on public.appointments for update to authenticated
using ((patient_id = (select auth.uid()) and status = 'Pendente') or (select public.is_admin()))
with check ((patient_id = (select auth.uid()) and status in ('Pendente','Cancelada')) or (select public.is_admin()));

-- Dados iniciais demonstrativos. Ajuste os endereços e telefones antes de usar.
insert into public.units(name,address,phone) values
 ('Unidade Central','Centro - São João do Pacuí','(38) 0000-0000'),
 ('Unidade de Saúde Bairro','Bairro - São João do Pacuí','(38) 0000-0001')
on conflict (name) do nothing;
insert into public.specialties(name) values
 ('Clínica Geral'),('Pediatria'),('Odontologia'),('Enfermagem')
on conflict (name) do nothing;
insert into public.professionals(name,specialty_id,unit_id)
select 'Dra. Ana Souza', s.id, u.id from public.specialties s, public.units u
where s.name='Clínica Geral' and u.name='Unidade Central'
and not exists (select 1 from public.professionals where name='Dra. Ana Souza');

-- Depois que a pessoa administradora criar sua conta pelo site, execute:
-- update public.profiles set role = 'admin' where email = 'SEU_EMAIL_DE_ADMIN';
