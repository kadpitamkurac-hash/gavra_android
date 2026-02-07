import 'package:supabase_flutter/supabase_flutter.dart';

class UserAuditService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Logs a user change to the user_daily_changes table
  /// Now supports only UUID-based registered passengers
  Future<void> logUserChange(String putnikIdentifier, String changeType) async {
    try {
      if (putnikIdentifier.isEmpty) {
        print('Invalid putnik identifier: $putnikIdentifier');
        return;
      }

      // Only UUID-based registered passengers are supported
      if (!_isUuid(putnikIdentifier)) {
        print('Only UUID-based passengers are supported: $putnikIdentifier');
        return;
      }

      final today = DateTime.now();
      final dateKey = today.toIso8601String().split('T')[0]; // YYYY-MM-DD format

      // For UUID-based registered passengers, use putnik_uuid column
      final existingRecord = await _supabase
          .from('user_daily_changes')
          .select()
          .eq('putnik_uuid', putnikIdentifier)
          .eq('datum', dateKey)
          .maybeSingle();

      if (existingRecord != null) {
        // Update existing record
        await _supabase.from('user_daily_changes').update({
          'changes_count': existingRecord['changes_count'] + 1,
          'last_change_at': today.toIso8601String(),
        }).eq('id', existingRecord['id']);
      } else {
        // Create new record
        await _supabase.from('user_daily_changes').insert({
          'putnik_uuid': putnikIdentifier,
          'datum': dateKey,
          'changes_count': 1,
          'last_change_at': today.toIso8601String(),
        });
      }
    } catch (e) {
      print('Error logging user change: $e');
      // Don't throw error to avoid breaking user operations
    }
  }

  /// Check if identifier is a UUID (registered passenger)
  bool _isUuid(String identifier) {
    // UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
    return uuidRegex.hasMatch(identifier);
  }

  /// Gets today's statistics for all users
  Future<List<Map<String, dynamic>>> getTodayStats() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      final response = await _supabase
          .from('user_daily_changes')
          .select('putnik_id, changes_count, last_change_at')
          .eq('datum', today)
          .order('changes_count', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting today stats: $e');
      return [];
    }
  }

  /// Gets change history for a specific user
  /// Now supports only UUID-based registered passengers
  Future<List<Map<String, dynamic>>> getUserChangeHistory(String putnikIdentifier) async {
    try {
      if (putnikIdentifier.isEmpty) {
        return [];
      }

      // Only UUID-based registered passengers are supported
      if (!_isUuid(putnikIdentifier)) {
        print('Only UUID-based passengers are supported: $putnikIdentifier');
        return [];
      }

      final response = await _supabase
          .from('user_daily_changes')
          .select('datum, changes_count, last_change_at')
          .eq('putnik_uuid', putnikIdentifier)
          .order('datum', ascending: false)
          .limit(30); // Last 30 days

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting user change history: $e');
      return [];
    }
  }

  /// Cleans up old audit records (older than 90 days)
  Future<void> cleanupOldRecords() async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 90));
      final cutoffString = cutoffDate.toIso8601String().split('T')[0];

      await _supabase.from('user_daily_changes').delete().lt('datum', cutoffString);

      print('Cleaned up user audit records older than $cutoffString');
    } catch (e) {
      print('Error cleaning up old audit records: $e');
    }
  }
}
