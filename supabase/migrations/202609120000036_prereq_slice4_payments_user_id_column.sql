ALTER TABLE public.payments
ADD COLUMN user_id UUID GENERATED ALWAYS AS (created_by) STORED;

COMMENT ON COLUMN public.payments.user_id IS
'Stored generated compatibility column mirroring created_by for RLS policy access.';
