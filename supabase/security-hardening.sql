-- Groomd Supabase security hardening
-- Applied to the existing deployed schema on 2026-09-06.
-- This is not a complete bootstrap schema. Review before applying elsewhere.

BEGIN;

REVOKE ALL PRIVILEGES ON TABLE
  public.bookings,
  public.business_amenities,
  public.business_owners,
  public.business_services,
  public.business_staff,
  public.businesses,
  public.profiles
FROM anon, authenticated;

GRANT SELECT ON TABLE
  public.business_amenities,
  public.business_services,
  public.business_staff,
  public.businesses
TO anon, authenticated;

GRANT SELECT ON TABLE public.business_owners TO authenticated;
GRANT SELECT ON TABLE public.bookings TO authenticated;

GRANT INSERT (
  business_id,
  business_name,
  service_name,
  staff_name,
  booking_date,
  booking_time,
  price,
  status,
  customer_id,
  customer_name,
  customer_phone,
  customer_email,
  payment_method,
  note
) ON TABLE public.bookings TO authenticated;

GRANT UPDATE (status) ON TABLE public.bookings TO authenticated;

GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE (full_name, phone) ON TABLE public.profiles TO authenticated;

DROP POLICY IF EXISTS "Guests can create bookings" ON public.bookings;

DROP POLICY IF EXISTS "Customers can create own bookings" ON public.bookings;

CREATE POLICY "Customers can create own bookings"
ON public.bookings
FOR INSERT
TO authenticated
WITH CHECK (
  customer_id = (SELECT auth.uid())
  AND status = 'upcoming'
);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;

ALTER TABLE public.bookings
  ALTER COLUMN business_id SET NOT NULL,
  ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_status_check
  CHECK (
    status IN (
      'pending',
      'upcoming',
      'confirmed',
      'completed',
      'cancelled'
    )
  );

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.profiles (id, full_name, phone, role)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data ->> 'full_name',
    NEW.raw_user_meta_data ->> 'phone',
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.get_booked_slots(bigint, text, date)
SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.get_booked_slots(bigint, text, date)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_booked_slots(bigint, text, date)
TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.handle_new_user()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()
FROM PUBLIC, anon, authenticated;

COMMIT;
