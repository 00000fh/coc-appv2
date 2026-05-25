import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

Future<void> initializeSupabase() async {
  await Supabase.initialize(
    url: 'https://pwgvrwksnmboxumtrrfi.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3Z3Zyd2tzbm1ib3h1bXRycmZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0MzAxMjcsImV4cCI6MjA5NTAwNjEyN30.ngC6Z1Qdopxetr7Au1MnUmF4ApaFATp7J2zDw_LW2LQ',
  );
}