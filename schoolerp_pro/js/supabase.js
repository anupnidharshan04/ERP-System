// js/supabase.js
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

class SupabaseClient {
  constructor() {
    this.supabaseUrl = window.SUPABASE_URL;
    this.supabaseKey = window.SUPABASE_ANON_KEY;
    this.client = createClient(this.supabaseUrl, this.supabaseKey);
  }

  // 🔹 Authentication
  async signIn(email, password) {
    const { data, error } = await this.client.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  }

  async signUp(email, password, userData = {}) {
    const { data, error } = await this.client.auth.signUp({
      email,
      password,
      options: { data: userData }
    });
    if (error) throw error;
    return data;
  }

  async signOut() {
    const { error } = await this.client.auth.signOut();
    if (error) throw error;
  }

  async getCurrentUser() {
    const { data: { user } } = await this.client.auth.getUser();
    return user;
  }

  // 🔹 Students
  async getStudents() {
    const { data, error } = await this.client
      .from("students")
      .select(`
        *,
        user_profiles(full_name, email, phone, gender, date_of_birth),
        classes(name, level, section, room_number)
      `)
      .order("created_at", { ascending: false });

    if (error) throw error;
    return data;
  }

  async createStudent(studentData) {
    const { data, error } = await this.client
      .from("students")
      .insert(studentData)
      .select("*")
      .single();
    if (error) throw error;
    return data;
  }

  async updateStudent(id, studentData) {
    const { data, error } = await this.client
      .from("students")
      .update(studentData)
      .eq("id", id)
      .select("*")
      .single();
    if (error) throw error;
    return data;
  }

  async deleteStudent(id) {
    const { error } = await this.client.from("students").delete().eq("id", id);
    if (error) throw error;
  }

  // 🔹 Teachers
  async getTeachers() {
    const { data, error } = await this.client
      .from("teachers")
      .select(`
        *,
        user_profiles(full_name, email, phone, gender, date_of_birth),
        teacher_subjects(
          subjects(name, code),
          classes(name, level, section)
        )
      `)
      .order("created_at", { ascending: false });

    if (error) throw error;
    return data;
  }

  async createTeacher(teacherData) {
    const { data, error } = await this.client
      .from("teachers")
      .insert(teacherData)
      .select("*")
      .single();
    if (error) throw error;
    return data;
  }

  async updateTeacher(id, teacherData) {
    const { data, error } = await this.client
      .from("teachers")
      .update(teacherData)
      .eq("id", id)
      .select("*")
      .single();
    if (error) throw error;
    return data;
  }

  async deleteTeacher(id) {
    const { error } = await this.client.from("teachers").delete().eq("id", id);
    if (error) throw error;
  }

  // 🔹 Classes & Subjects
  async getClasses() {
    const { data, error } = await this.client.from("classes").select("*").order("level");
    if (error) throw error;
    return data;
  }

  async getSubjects() {
    const { data, error } = await this.client.from("subjects").select("*").order("name");
    if (error) throw error;
    return data;
  }

  // 🔹 File Upload
  async uploadFile(bucket, filePath, file) {
    const { data, error } = await this.client.storage.from(bucket).upload(filePath, file, {
      upsert: true
    });
    if (error) throw error;
    return data;
  }

  async getFileUrl(bucket, filePath) {
    const { data } = await this.client.storage.from(bucket).getPublicUrl(filePath);
    return data.publicUrl;
  }

  async deleteFile(bucket, filePath) {
    const { error } = await this.client.storage.from(bucket).remove([filePath]);
    if (error) throw error;
  }
}

// ✅ Export as module
export const supabaseClient = new SupabaseClient();
