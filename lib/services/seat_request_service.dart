import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/realtime_manager.dart';
import 'realtime_notification_service.dart';

/// Servis za upravljanje aktivnim zahtevima za sedišta (seat_requests tabela)
class SeatRequestService {
  static SupabaseClient get _supabase => supabase;

  static StreamSubscription? _requestsSubscription;
  static final StreamController<List<Map<String, dynamic>>> _requestsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  /// 📥 INSERT U SEAT_REQUESTS TABELU ZA BACKEND OBRADU
  /// Insert a seat request into `seat_requests` table for backend processing.
  /// Returns true when insert succeeded (row created), false otherwise.
  static Future<bool> insertSeatRequest({
    required String putnikId,
    required String dan,
    required String vreme,
    required String grad,
    int brojMesta = 1,
  }) async {
    try {
      final datum = getNextDateForDay(DateTime.now(), dan);

      // Check if already exists a pending request for same putnik, grad, datum, vreme
      final existing = await _supabase
          .from('seat_requests')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('grad', grad.toUpperCase())
          .eq('datum', datum.toIso8601String().split('T')[0])
          .eq('zeljeno_vreme', vreme)
          .eq('status', 'pending')
          .maybeSingle();

      if (existing != null) {
        debugPrint('⚠️ [SeatRequestService] Pending request already exists for $putnikId $grad $dan $vreme');
        return false; // Already exists
      }

      // Attempt insert and return created row (safe check)
      final inserted = await _supabase
          .from('seat_requests')
          .insert({
            'putnik_id': putnikId,
            'grad': grad.toUpperCase(),
            'datum': datum.toIso8601String().split('T')[0],
            'zeljeno_vreme': vreme,
            'status': 'pending',
            'broj_mesta': brojMesta,
          })
          .select()
          .maybeSingle();

      if (inserted == null) {
        // Insert returned no row - treat as failure and log audit
        debugPrint('❌ [SeatRequestService] Insert returned null (possible permission failure)');
        try {
          await _supabase.from('admin_audit_logs').insert({
            'action_type': 'SEAT_REQUEST_FAILED',
            'details': 'Seat request insert returned null for $putnikId',
            'admin_name': 'system',
            'metadata': {
              'putnik_id': putnikId,
              'grad': grad,
              'datum': datum.toIso8601String().split('T')[0],
              'zeljeno_vreme': vreme,
              'broj_mesta': brojMesta,
            },
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
        return false;
      }

      debugPrint(
          '✅ [SeatRequestService] Inserted for $grad $vreme on $dan (Datum: ${datum.toIso8601String().split('T')[0]})');
      return true;
    } catch (e) {
      debugPrint('❌ [SeatRequestService] Error inserting seat request: $e');

      try {
        await _supabase.from('admin_audit_logs').insert({
          'action_type': 'SEAT_REQUEST_FAILED',
          'details': 'Error inserting seat request',
          'admin_name': 'system',
          'metadata': {
            'error': e.toString(),
            'putnik_id': putnikId,
            'grad': grad,
            'dan': dan,
            'vreme': vreme,
            'broj_mesta': brojMesta,
          },
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      // Notify admins so they can investigate immediately
      try {
        await RealtimeNotificationService.sendNotificationToAdmins(
          title: '⚠️ Seat request failed',
          body: 'Seat request insert failed for $putnikId ($grad $vreme)',
          data: {'putnik_id': putnikId, 'grad': grad, 'vreme': vreme},
        );
      } catch (_) {}

      return false;
    }
  }

  /// Dohvata aktivne zahteve
  static Future<List<Map<String, dynamic>>> getActiveRequests() async {
    try {
      final response = await _supabase.from('seat_requests').select().eq('status', 'pending').order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// 🕒 STREAM SVIH AKTIVNIH ZAHTEVA - Za admin monitoring
  static Stream<List<Map<String, dynamic>>> streamActiveRequests() {
    if (_requestsSubscription == null) {
      _requestsSubscription = RealtimeManager.instance.subscribe('seat_requests').listen((payload) {
        _refreshRequestsStream();
      });
      // Inicijalno učitavanje
      _refreshRequestsStream();
    }
    return _requestsController.stream;
  }

  static void _refreshRequestsStream() async {
    final requests = await getActiveRequests();
    if (!_requestsController.isClosed) {
      _requestsController.add(requests);
    }
  }

  /// 🧹 Čisti realtime subscription
  static void dispose() {
    _requestsSubscription?.cancel();
    _requestsSubscription = null;
    _requestsController.close();
  }

  /// 📅 Helper: Računa sledeći datum za dati dan u nedelji
  static DateTime getNextDateForDay(DateTime fromDate, String danKratica) {
    const daniMap = {'pon': 1, 'uto': 2, 'sre': 3, 'cet': 4, 'pet': 5, 'sub': 6, 'ned': 7};
    final targetWeekday = daniMap[danKratica.toLowerCase()] ?? 1;
    final currentWeekday = fromDate.weekday;

    int daysToAdd = targetWeekday - currentWeekday;
    if (daysToAdd < 0) daysToAdd += 7;

    return fromDate.add(Duration(days: daysToAdd));
  }
}
