import '../../core/supabase_config.dart';

class NotificationService {
  static Future<void> notifyLab({
    required String labId,
    required String recordId,
    required String title,
    required String message,
    String type = 'info',
  }) async {
    await supabase.from('app_notifications').insert({
      'lab_id': labId,
      'coc_record_id': recordId,
      'title': title,
      'message': message,
      'type': type,
    });
  }

  static Future<void> notifyRole({
    required String role,
    required String recordId,
    required String title,
    required String message,
    String type = 'info',
  }) async {
    await supabase.from('app_notifications').insert({
      'role': role,
      'coc_record_id': recordId,
      'title': title,
      'message': message,
      'type': type,
    });
  }

  static Future<void> notifyUser({
    required String userId,
    required String recordId,
    required String title,
    required String message,
    String type = 'info',
  }) async {
    await supabase.from('app_notifications').insert({
      'user_id': userId,
      'coc_record_id': recordId,
      'title': title,
      'message': message,
      'type': type,
    });
  }

  static Future<void> createReminderOnce({
    required String reminderKey,
    required String role,
    required String recordId,
    required String title,
    required String message,
    String type = 'reminder',
  }) async {
    try {
      await supabase.from('app_notifications').insert({
        'reminder_key': reminderKey,
        'role': role,
        'coc_record_id': recordId,
        'title': title,
        'message': message,
        'type': type,
      });
    } catch (_) {
      // Duplicate reminder_key means reminder already created.
    }
  }
}