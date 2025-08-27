-- Location: supabase/migrations/20250826083933_school_erp_system.sql
-- Schema Analysis: No existing schema found - creating complete school ERP system
-- Integration Type: Complete new implementation with authentication
-- Dependencies: None - fresh implementation

-- 1. Custom Types for School System
CREATE TYPE public.user_role AS ENUM ('admin', 'teacher', 'student', 'parent');
CREATE TYPE public.gender AS ENUM ('male', 'female', 'other');
CREATE TYPE public.enrollment_status AS ENUM ('active', 'inactive', 'graduated', 'transferred');
CREATE TYPE public.employment_status AS ENUM ('active', 'inactive', 'on_leave', 'terminated');
CREATE TYPE public.class_level AS ENUM ('grade_1', 'grade_2', 'grade_3', 'grade_4', 'grade_5', 'grade_6', 'grade_7', 'grade_8', 'grade_9', 'grade_10', 'grade_11', 'grade_12');

-- 2. Core User Profiles Table (Critical intermediary)
CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    role public.user_role DEFAULT 'student'::public.user_role,
    phone TEXT,
    address TEXT,
    date_of_birth DATE,
    gender public.gender,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. Classes/Sections Table
CREATE TABLE public.classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL, -- e.g., "10-A", "Grade 5-B"
    level public.class_level NOT NULL,
    section TEXT NOT NULL, -- A, B, C, etc.
    capacity INTEGER DEFAULT 30,
    academic_year TEXT NOT NULL, -- e.g., "2024-2025"
    room_number TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 4. Subjects Table
CREATE TABLE public.subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    code TEXT UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. Students Table (References user_profiles)
CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    student_id TEXT NOT NULL UNIQUE,
    class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
    enrollment_status public.enrollment_status DEFAULT 'active'::public.enrollment_status,
    admission_date DATE NOT NULL,
    parent_name TEXT,
    parent_phone TEXT,
    parent_email TEXT,
    emergency_contact TEXT,
    medical_notes TEXT,
    photo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 6. Teachers Table (References user_profiles)
CREATE TABLE public.teachers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    employee_id TEXT NOT NULL UNIQUE,
    employment_status public.employment_status DEFAULT 'active'::public.employment_status,
    hire_date DATE NOT NULL,
    department TEXT,
    qualification TEXT,
    experience_years INTEGER DEFAULT 0,
    salary DECIMAL(10,2),
    emergency_contact TEXT,
    photo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 7. Teacher-Subject Assignments
CREATE TABLE public.teacher_subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID REFERENCES public.teachers(id) ON DELETE CASCADE,
    subject_id UUID REFERENCES public.subjects(id) ON DELETE CASCADE,
    class_id UUID REFERENCES public.classes(id) ON DELETE CASCADE,
    academic_year TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(teacher_id, subject_id, class_id, academic_year)
);

-- 8. Essential Indexes
CREATE INDEX idx_user_profiles_role ON public.user_profiles(role);
CREATE INDEX idx_user_profiles_email ON public.user_profiles(email);
CREATE INDEX idx_students_student_id ON public.students(student_id);
CREATE INDEX idx_students_class_id ON public.students(class_id);
CREATE INDEX idx_students_user_id ON public.students(user_id);
CREATE INDEX idx_teachers_employee_id ON public.teachers(employee_id);
CREATE INDEX idx_teachers_user_id ON public.teachers(user_id);
CREATE INDEX idx_classes_level ON public.classes(level);
CREATE INDEX idx_teacher_subjects_teacher_id ON public.teacher_subjects(teacher_id);
CREATE INDEX idx_teacher_subjects_subject_id ON public.teacher_subjects(subject_id);

-- 9. Storage Buckets for Student/Teacher Photos and Documents
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
    ('student-photos', 'student-photos', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']),
    ('teacher-photos', 'teacher-photos', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']),
    ('documents', 'documents', false, 10485760, ARRAY['application/pdf', 'application/msword', 'image/jpeg', 'image/png']);

-- 10. Functions (MUST BE BEFORE RLS POLICIES)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.user_profiles (id, email, full_name, role)
    VALUES (
        NEW.id, 
        NEW.email, 
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        COALESCE(NEW.raw_user_meta_data->>'role', 'student')::public.user_role
    );
    RETURN NEW;
END;
$$;

-- Helper function for role-based access using auth.users metadata
CREATE OR REPLACE FUNCTION public.is_admin_from_auth()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
SELECT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id = auth.uid() 
    AND (au.raw_user_meta_data->>'role' = 'admin' 
         OR au.raw_app_meta_data->>'role' = 'admin')
)
$$;

-- 11. Enable RLS on All Tables
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_subjects ENABLE ROW LEVEL SECURITY;

-- 12. RLS Policies - Using Correct Patterns

-- Pattern 1: Core user table - Simple, no functions
CREATE POLICY "users_manage_own_user_profiles"
ON public.user_profiles
FOR ALL
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Admin access to all user profiles using auth metadata
CREATE POLICY "admin_full_access_user_profiles"
ON public.user_profiles
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

-- Pattern 4: Public read for classes and subjects, admin write
CREATE POLICY "public_can_read_classes"
ON public.classes
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "admin_manage_classes"
ON public.classes
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

CREATE POLICY "public_can_read_subjects"
ON public.subjects
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "admin_manage_subjects"
ON public.subjects
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

-- Pattern 2: Students - users can manage their own records, admins can manage all
CREATE POLICY "users_view_own_students"
ON public.students
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.is_admin_from_auth());

CREATE POLICY "admin_manage_students"
ON public.students
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

-- Pattern 2: Teachers - users can view their own records, admins can manage all
CREATE POLICY "users_view_own_teachers"
ON public.teachers
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.is_admin_from_auth());

CREATE POLICY "admin_manage_teachers"
ON public.teachers
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

-- Teacher-subject assignments
CREATE POLICY "view_teacher_subjects"
ON public.teacher_subjects
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "admin_manage_teacher_subjects"
ON public.teacher_subjects
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

-- 13. Storage RLS Policies

-- Student photos - Private access
CREATE POLICY "users_view_own_student_photos"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'student-photos' AND (owner = auth.uid() OR public.is_admin_from_auth()));

CREATE POLICY "admin_manage_student_photos"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'student-photos' AND public.is_admin_from_auth())
WITH CHECK (bucket_id = 'student-photos' AND public.is_admin_from_auth());

-- Teacher photos - Private access
CREATE POLICY "users_view_own_teacher_photos"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'teacher-photos' AND (owner = auth.uid() OR public.is_admin_from_auth()));

CREATE POLICY "admin_manage_teacher_photos"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'teacher-photos' AND public.is_admin_from_auth())
WITH CHECK (bucket_id = 'teacher-photos' AND public.is_admin_from_auth());

-- Documents - Private access
CREATE POLICY "admin_manage_documents"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'documents' AND public.is_admin_from_auth())
WITH CHECK (bucket_id = 'documents' AND public.is_admin_from_auth());

-- 14. Trigger for Auto User Profile Creation
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 15. Mock Data for Development
DO $$
DECLARE
    admin_uuid UUID := gen_random_uuid();
    teacher1_uuid UUID := gen_random_uuid();
    teacher2_uuid UUID := gen_random_uuid();
    student1_uuid UUID := gen_random_uuid();
    student2_uuid UUID := gen_random_uuid();
    student3_uuid UUID := gen_random_uuid();
    class1_id UUID := gen_random_uuid();
    class2_id UUID := gen_random_uuid();
    math_subject_id UUID := gen_random_uuid();
    english_subject_id UUID := gen_random_uuid();
    science_subject_id UUID := gen_random_uuid();
    teacher1_id UUID;
    teacher2_id UUID;
BEGIN
    -- Create auth users with complete field structure
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        created_at, updated_at, raw_user_meta_data, raw_app_meta_data,
        is_sso_user, is_anonymous, confirmation_token, confirmation_sent_at,
        recovery_token, recovery_sent_at, email_change_token_new, email_change,
        email_change_sent_at, email_change_token_current, email_change_confirm_status,
        reauthentication_token, reauthentication_sent_at, phone, phone_change,
        phone_change_token, phone_change_sent_at
    ) VALUES
        (admin_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'admin@schoolerp.com', crypt('admin123', gen_salt('bf', 10)), now(), now(), now(),
         '{"full_name": "John Anderson", "role": "admin"}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb,
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (teacher1_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'teacher1@schoolerp.com', crypt('teacher123', gen_salt('bf', 10)), now(), now(), now(),
         '{"full_name": "Sarah Wilson", "role": "teacher"}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb,
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (teacher2_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'teacher2@schoolerp.com', crypt('teacher123', gen_salt('bf', 10)), now(), now(), now(),
         '{"full_name": "Michael Brown", "role": "teacher"}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb,
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (student1_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'student1@schoolerp.com', crypt('student123', gen_salt('bf', 10)), now(), now(), now(),
         '{"full_name": "Emma Johnson", "role": "student"}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb,
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (student2_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'student2@schoolerp.com', crypt('student123', gen_salt('bf', 10)), now(), now(), now(),
         '{"full_name": "David Martinez", "role": "student"}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb,
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (student3_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'student3@schoolerp.com', crypt('student123', gen_salt('bf', 10)), now(), now(), now(),
         '{"full_name": "Sophia Davis", "role": "student"}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb,
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null);

    -- Create classes
    INSERT INTO public.classes (id, name, level, section, academic_year, room_number) VALUES
        (class1_id, '10-A', 'grade_10', 'A', '2024-2025', '101'),
        (class2_id, '9-B', 'grade_9', 'B', '2024-2025', '102');

    -- Create subjects
    INSERT INTO public.subjects (id, name, code) VALUES
        (math_subject_id, 'Mathematics', 'MATH'),
        (english_subject_id, 'English Literature', 'ENG'),
        (science_subject_id, 'Physical Science', 'SCI');

    -- Create teachers and get their IDs
    INSERT INTO public.teachers (id, user_id, employee_id, hire_date, department, qualification, experience_years)
    VALUES
        (gen_random_uuid(), teacher1_uuid, 'T001', '2020-08-15', 'Mathematics', 'M.Sc Mathematics', 5),
        (gen_random_uuid(), teacher2_uuid, 'T002', '2019-07-20', 'English', 'M.A English Literature', 8);

    -- Get teacher IDs for assignments
    SELECT id INTO teacher1_id FROM public.teachers WHERE user_id = teacher1_uuid;
    SELECT id INTO teacher2_id FROM public.teachers WHERE user_id = teacher2_uuid;

    -- Create students
    INSERT INTO public.students (user_id, student_id, class_id, admission_date, parent_name, parent_phone, parent_email)
    VALUES
        (student1_uuid, 'S001', class1_id, '2024-04-01', 'Robert Johnson', '+1234567890', 'robert.johnson@email.com'),
        (student2_uuid, 'S002', class2_id, '2024-04-01', 'Maria Martinez', '+1234567891', 'maria.martinez@email.com'),
        (student3_uuid, 'S003', class1_id, '2024-04-01', 'James Davis', '+1234567892', 'james.davis@email.com');

    -- Assign teachers to subjects
    INSERT INTO public.teacher_subjects (teacher_id, subject_id, class_id, academic_year) VALUES
        (teacher1_id, math_subject_id, class1_id, '2024-2025'),
        (teacher1_id, math_subject_id, class2_id, '2024-2025'),
        (teacher2_id, english_subject_id, class1_id, '2024-2025'),
        (teacher2_id, english_subject_id, class2_id, '2024-2025');

EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'Foreign key error: %', SQLERRM;
    WHEN unique_violation THEN
        RAISE NOTICE 'Unique constraint error: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'Unexpected error: %', SQLERRM;
END $$;

-- 16. Cleanup Function for Development
CREATE OR REPLACE FUNCTION public.cleanup_school_test_data()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    auth_user_ids_to_delete UUID[];
BEGIN
    -- Get auth user IDs for school system
    SELECT ARRAY_AGG(id) INTO auth_user_ids_to_delete
    FROM auth.users
    WHERE email LIKE '%@schoolerp.com';

    -- Delete in dependency order (children first)
    DELETE FROM public.teacher_subjects WHERE teacher_id IN (
        SELECT id FROM public.teachers WHERE user_id = ANY(auth_user_ids_to_delete)
    );
    DELETE FROM public.students WHERE user_id = ANY(auth_user_ids_to_delete);
    DELETE FROM public.teachers WHERE user_id = ANY(auth_user_ids_to_delete);
    DELETE FROM public.user_profiles WHERE id = ANY(auth_user_ids_to_delete);

    -- Delete auth.users last
    DELETE FROM auth.users WHERE id = ANY(auth_user_ids_to_delete);

    -- Clean up classes and subjects
    DELETE FROM public.classes WHERE academic_year = '2024-2025';
    DELETE FROM public.subjects WHERE code IN ('MATH', 'ENG', 'SCI');

EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'Foreign key constraint prevents deletion: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'Cleanup failed: %', SQLERRM;
END $$;