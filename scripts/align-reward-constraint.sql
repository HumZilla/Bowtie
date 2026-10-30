-- Match current trigger amounts while retaining historical immutable snapshots.
ALTER TABLE public.bowtie_rewards DROP CONSTRAINT bowtie_rewards_check;
ALTER TABLE public.bowtie_rewards ADD CONSTRAINT bowtie_rewards_check CHECK (
 (tier='white' AND amount=100) OR
 (tier='black' AND amount IN (150,250)) OR
 (tier='purple' AND amount IN (200,375)) OR
 (tier='gold' AND amount IN (250,500))
);
