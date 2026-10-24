alter table public.bowtie_testimonials alter column vehicle drop not null;
alter table public.bowtie_testimonials drop constraint if exists bowtie_testimonials_vehicle_check;
alter table public.bowtie_testimonials add constraint bowtie_testimonials_vehicle_check check (vehicle is null or char_length(vehicle) between 3 and 120);
alter table public.bowtie_testimonials add column if not exists moment_type text not null default 'other';
alter table public.bowtie_testimonials drop constraint if exists bowtie_testimonials_moment_type_check;
alter table public.bowtie_testimonials add constraint bowtie_testimonials_moment_type_check check (moment_type in ('purchase','referral','reward','service','community','other'));