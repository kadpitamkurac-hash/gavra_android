import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/putnik.dart';
import '../models/registrovani_putnik.dart';
import '../utils/date_utils.dart';
import '../utils/grad_adresa_validator.dart';
import '../utils/vozac_boja.dart';
import 'admin_audit_service.dart';
import 'realtime/realtime_manager.dart';
import 'slobodna_mesta_service.dart';
import 'user_audit_service.dart';
import 'vozac_mapping_service.dart';
import 'voznje_log_service.dart';

/// Servis za upravljanje mesečnim putnicima (normalizovana šema)
class RegistrovaniPutnikService {
  RegistrovaniPutnikService({SupabaseClient? supabaseClient}) : _supabaseOverride = supabaseClient;
  final SupabaseClient? _supabaseOverride;

  SupabaseClient get _supabase => _supabaseOverride ?? supabase;

  // Helper method to convert ISO date to day abbreviation
  static String _isoDateToDayAbbr(String isoDate) {
    final dt = DateTime.parse(isoDate);
    const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
    return dani[dt.weekday - 1];
  }

  // 🔧 SINGLETON PATTERN za realtime stream - koristi RealtimeManager
  static StreamController<List<RegistrovaniPutnik>>? _sharedController;
  static StreamSubscription? _sharedSubscription;
  static RealtimeChannel? _realtimeChannel;
  static List<RegistrovaniPutnik>? _lastValue;

  // 🔧 SINGLETON PATTERN za "SVI PUTNICI" stream (uključujući neaktivne)
  static StreamController<List<RegistrovaniPutnik>>? _sharedSviController;
  static StreamSubscription? _sharedSviSubscription;
  static List<RegistrovaniPutnik>? _lastSviValue;

  /// Dohvata sve mesečne putnike
  Future<List<RegistrovaniPutnik>> getAllRegistrovaniPutnici() async {
    final response = await _supabase.from('registrovani_putnici').select('''
          *
        ''').eq('obrisan', false).eq('is_duplicate', false).order('putnik_ime');

    return response.map((json) => RegistrovaniPutnik.fromMap(json)).toList();
  }

  /// Dohvata sve putnike (legacy compatibility)
  Future<List<Putnik>> getAllPutnici() async {
    final registrovani = await getAllRegistrovaniPutnici();
    final allPutnici = <Putnik>[];

    for (final item in registrovani) {
      final putnici = Putnik.fromRegistrovaniPutniciMultiple(item.toMap());
      allPutnici.addAll(putnici);
    }

    return allPutnici;
  }

  /// Dohvata aktivne mesečne putnike
  Future<List<RegistrovaniPutnik>> getAktivniregistrovaniPutnici() async {
    final response = await _supabase.from('registrovani_putnici').select('''
          *
        ''').eq('aktivan', true).eq('obrisan', false).eq('is_duplicate', false).order('putnik_ime');

    return response.map((json) => RegistrovaniPutnik.fromMap(json)).toList();
  }

  /// Dohvata putnike kojima treba račun (treba_racun = true)
  Future<List<RegistrovaniPutnik>> getPutniciZaRacun() async {
    final response = await _supabase
        .from('registrovani_putnici')
        .select('*')
        .eq('aktivan', true)
        .eq('obrisan', false)
        .eq('treba_racun', true)
        .eq('is_duplicate', false)
        .order('putnik_ime');

    return response.map((json) => RegistrovaniPutnik.fromMap(json)).toList();
  }

  /// Dohvata mesečnog putnika po ID-u
  Future<RegistrovaniPutnik?> getRegistrovaniPutnikById(String id) async {
    final response = await _supabase.from('registrovani_putnici').select('''
          *
        ''').eq('id', id).single();

    return RegistrovaniPutnik.fromMap(response);
  }

  /// Dohvata više registrovanih putnika po ID-evima
  Future<List<RegistrovaniPutnik>> getRegistrovaniPutniciByIds(List<dynamic> ids) async {
    if (ids.isEmpty) return [];

    final stringIds = ids.map((id) => id.toString()).toList();
    final response = await _supabase.from('registrovani_putnici').select('''
          *
        ''').inFilter('id', stringIds);

    return response.map((row) => RegistrovaniPutnik.fromMap(row)).toList();
  }

  /// Dohvata mesečnog putnika po imenu (legacy compatibility)
  static Future<RegistrovaniPutnik?> getRegistrovaniPutnikByIme(String ime) async {
    try {
      final response = await supabase
          .from('registrovani_putnici')
          .select()
          .eq('putnik_ime', ime)
          .eq('obrisan', false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return RegistrovaniPutnik.fromMap(response);
    } catch (e) {
      return null;
    }
  }

  /// 🔧 SINGLETON STREAM za mesečne putnike - koristi RealtimeManager
  /// Svi pozivi dele isti controller
  static Stream<List<RegistrovaniPutnik>> streamAktivniRegistrovaniPutnici() {
    // Ako već postoji aktivan controller, koristi ga
    if (_sharedController != null && !_sharedController!.isClosed) {
      // NE POVEĆAVAJ listener count - broadcast stream deli istu pretplatu
      // debugPrint('📊 [RegistrovaniPutnikService] Reusing existing stream'); // Disabled - too spammy

      // Emituj poslednju vrednost novom listener-u
      if (_lastValue != null) {
        Future.microtask(() {
          if (_sharedController != null && !_sharedController!.isClosed) {
            _sharedController!.add(_lastValue!);
          }
        });
      }

      return _sharedController!.stream;
    }

    // Kreiraj novi shared controller
    _sharedController = StreamController<List<RegistrovaniPutnik>>.broadcast();

    // Učitaj inicijalne podatke
    _fetchAndEmit(supabase);

    // Kreiraj subscription preko RealtimeManager
    _setupRealtimeSubscription(supabase);

    return _sharedController!.stream;
  }

  /// Stream za Putnik objekte (legacy compatibility)
  static Stream<List<Putnik>> streamPutnici() {
    return streamAktivniRegistrovaniPutnici().map((registrovani) {
      final allPutnici = <Putnik>[];

      for (final item in registrovani) {
        final registrovaniPutnici = Putnik.fromRegistrovaniPutniciMultiple(item.toMap());
        allPutnici.addAll(registrovaniPutnici);
      }
      return allPutnici;
    });
  }

  /// Stream za kombinovane putnike filtrirane po datumu (legacy compatibility)
  static Stream<List<Putnik>> streamKombinovaniPutniciFiltered({
    String? isoDate,
    String? grad,
    String? vreme,
  }) {
    return streamAktivniRegistrovaniPutnici().map((registrovani) {
      final allPutnici = <Putnik>[];

      for (final item in registrovani) {
        final dayAbbr = isoDate != null ? _isoDateToDayAbbr(isoDate) : null;
        final registrovaniPutnici = dayAbbr != null
            ? Putnik.fromRegistrovaniPutniciMultipleForDay(item.toMap(), dayAbbr, isoDate: isoDate)
            : Putnik.fromRegistrovaniPutniciMultiple(item.toMap());

        allPutnici.addAll(registrovaniPutnici);
      }

      // Filter by grad if provided
      if (grad != null) {
        allPutnici.retainWhere((p) => p.grad == grad);
      }

      // Filter by vreme if provided
      if (vreme != null) {
        allPutnici.retainWhere((p) => p.polazak == vreme);
      }

      return allPutnici;
    });
  }

  /// Fetch putnici za određeni dan (legacy compatibility)
  Future<List<Putnik>> getPutniciByDayIso(String isoDate) async {
    final dayAbbr = _isoDateToDayAbbr(isoDate);
    final registrovani = await getAktivniregistrovaniPutnici();
    final allPutnici = <Putnik>[];

    for (final item in registrovani) {
      final putniciZaDan = Putnik.fromRegistrovaniPutniciMultipleForDay(item.toMap(), dayAbbr, isoDate: isoDate);
      allPutnici.addAll(putniciZaDan);
    }

    return allPutnici;
  }

  /// 🔄 Fetch podatke i emituj u stream
  static Future<void> _fetchAndEmit(SupabaseClient supabase) async {
    try {
      debugPrint('📊 [RegistrovaniPutnik] Osvežavanje liste putnika iz baze...');

      // 🔧 POJEDNOSTAVLJEN QUERY - direktno bez lanaca za pouzdanost
      final data = await supabase.from('registrovani_putnici').select();

      // Filtriraj lokalno umesto preko Supabase
      final putnici = data
          .where((json) {
            final aktivan = json['aktivan'] as bool? ?? false;
            final obrisan = json['obrisan'] as bool? ?? true;
            final isDuplicate = json['is_duplicate'] as bool? ?? false;
            return aktivan && !obrisan && !isDuplicate;
          })
          .map((json) => RegistrovaniPutnik.fromMap(json))
          .toList()
        ..sort((a, b) => a.putnikIme.compareTo(b.putnikIme));

      debugPrint('✅ [RegistrovaniPutnik] Učitano ${putnici.length} putnika (nakon filtriranja)');

      _lastValue = putnici;

      if (_sharedController != null && !_sharedController!.isClosed) {
        _sharedController!.add(putnici);
        debugPrint('🔊 [RegistrovaniPutnik] Stream emitovao listu sa ${putnici.length} putnika');
      } else {
        debugPrint('⚠️ [RegistrovaniPutnik] Controller nije dostupan ili je zatvoren');
      }
    } catch (e) {
      debugPrint('🔴 [RegistrovaniPutnik] Error fetching passengers: $e');
    }
  }

  /// 🔌 Setup realtime subscription - Koristi payload za partial updates
  static void _setupRealtimeSubscription(SupabaseClient supabase) {
    _sharedSubscription?.cancel();

    debugPrint('🔗 [RegistrovaniPutnik] Setup realtime subscription...');
    // Koristi centralizovani RealtimeManager
    _sharedSubscription = RealtimeManager.instance.subscribe('registrovani_putnici').listen((payload) {
      _handleRealtimeUpdate(payload);
    }, onError: (error) {
      debugPrint('❌ [RegistrovaniPutnik] Stream error: $error');
    });
  }

  /// 🔄 Handle realtime update koristeći payload umesto full refetch
  static void _handleRealtimeUpdate(PostgresChangePayload payload) {
    if (_lastValue == null) {
      return;
    }

    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;

    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
        _handleInsert(newRecord);
        break;
      case PostgresChangeEvent.update:
        _handleUpdate(newRecord, oldRecord);
        break;
      default:
        break;
    }
  }

  /// ➕ Handle INSERT event
  static void _handleInsert(Map<String, dynamic> newRecord) {
    try {
      final putnik = RegistrovaniPutnik.fromMap(newRecord);

      // Proveri da li zadovoljava filter kriterijume (aktivan, nije obrisan, nije duplikat)
      final aktivan = newRecord['aktivan'] as bool? ?? false;
      final obrisan = newRecord['obrisan'] as bool? ?? true;
      final isDuplicate = newRecord['is_duplicate'] as bool? ?? false;

      if (!aktivan || obrisan || isDuplicate) {
        debugPrint('🔄 [RegistrovaniPutnik] INSERT ignorisan (ne zadovoljava filter): ${putnik.putnikIme}');
        return;
      }

      // Dodaj u listu i sortiraj
      _lastValue!.add(putnik);
      _lastValue!.sort((a, b) => a.putnikIme.compareTo(b.putnikIme));

      debugPrint('✅ [RegistrovaniPutnik] INSERT: Dodan ${putnik.putnikIme}');
      _emitUpdate();
    } catch (e) {
      debugPrint('❌ [RegistrovaniPutnik] INSERT error: $e');
    }
  }

  /// 🔄 Handle UPDATE event
  static void _handleUpdate(Map<String, dynamic> newRecord, Map<String, dynamic>? oldRecord) {
    try {
      final putnikId = newRecord['id'] as String?;
      if (putnikId == null) return;

      // 🔧 VAŽNO: Realtime payload može sadržavati samo delomičan update
      // Trebamo da preuzemo ceo rekord iz baze da bi svi polji bili dostupni
      // Međutim, to zahteva async, što nije moguće ovde
      // REŠENJE: Koristi _lastValue[index].toMap() kao fallback ako realtime payload nema sve polje

      final index = _lastValue!.indexWhere((p) => p.id == putnikId);

      if (newRecord.containsKey('polasci_po_danu')) {
        debugPrint('✅ [RegistrovaniPutnik] Realtime update - polasci_po_danu changed');
      }

      // Poseban debug za reset akciju
      final putnikIme = newRecord['putnik_ime'] as String? ?? (index >= 0 ? _lastValue![index].putnikIme : '');
      if (newRecord['status'] == 'radi' && newRecord.containsKey('polasci_po_danu')) {
        debugPrint('🔧 [RegistrovaniPutnik] RESET ACTION: $putnikIme - status=${'radi'}, polasci ažurirani');
      }

      // Merge sa starom vredošću ako postoji lokalno
      Map<String, dynamic> mergedRecord = {};
      if (index != -1) {
        // Kreni sa starom vredošću
        mergedRecord = _lastValue![index].toMap();

        // POSEBAN SLUČAJ: Ako je newRecord parcijalan (realtime update bez svih polja),
        // a status je 'radi' (što ukazuje na reset), trebam biti siguran da je polasci osvežen
        if (newRecord['status'] == 'radi' && !newRecord.containsKey('polasci_po_danu')) {
          debugPrint('⚠️ [RegistrovaniPutnik] RESET bez polasci_po_danu - parcijalan payload!');
        }
      } else {
        // Ako nema u _lastValue, kreni sa newRecord
        mergedRecord = Map<String, dynamic>.from(newRecord);
      }

      // Nadpiši sa novim vrednostima iz realtime update-a
      mergedRecord.addAll(newRecord);

      // Debug: Log šta se merdžuje za reset
      if (mergedRecord['putnik_ime'] != null && (mergedRecord['putnik_ime'] as String).contains('Dušica')) {
        debugPrint(
            '🔀 [_handleUpdate] Merge za ${mergedRecord['putnik_ime']}: aktivan=${mergedRecord['aktivan']}, obrisan=${mergedRecord['obrisan']}, isDuplicate=${mergedRecord['is_duplicate']}');
        debugPrint('🔀 [_handleUpdate] polasci_po_danu=${mergedRecord['polasci_po_danu']}');
      }

      final updatedPutnik = RegistrovaniPutnik.fromMap(mergedRecord);

      // Proveri da li sada zadovoljava filter kriterijume
      final aktivan = mergedRecord['aktivan'] as bool? ?? false;
      final obrisan = mergedRecord['obrisan'] as bool? ?? true;
      final isDuplicate = mergedRecord['is_duplicate'] as bool? ?? false;
      final shouldBeIncluded = aktivan && !obrisan && !isDuplicate;

      if (mergedRecord['putnik_ime'] != null && (mergedRecord['putnik_ime'] as String).contains('Dušica')) {
        debugPrint(
            '✔️ [_handleUpdate] Dušica shouldBeIncluded=$shouldBeIncluded (aktivan=$aktivan, obrisan=$obrisan, isDuplicate=$isDuplicate)');
      }

      if (shouldBeIncluded) {
        if (index == -1) {
          // Možda je bio neaktivan, a sada je aktivan - dodaj
          _lastValue!.add(updatedPutnik);
          debugPrint('➕ [_handleUpdate] Dodao sam ${mergedRecord['putnik_ime']} u _lastValue');
        } else {
          // Update postojeći
          _lastValue![index] = updatedPutnik;
          debugPrint('🔄 [_handleUpdate] Ažurirao sam ${mergedRecord['putnik_ime']} u _lastValue');
        }
        _lastValue!.sort((a, b) => a.putnikIme.compareTo(b.putnikIme));

        // Debug: Log _lastValue nakon sort-a
        debugPrint('📊 [_handleUpdate] Sadržaj _lastValue nakon sort-a (${_lastValue!.length} putnika):');
        for (int i = 0; i < _lastValue!.length; i++) {
          final p = _lastValue![i];
          debugPrint('  [$i] ${p.putnikIme}');
        }
      } else {
        // Ukloni iz liste ako postoji
        if (index != -1) {
          _lastValue!.removeAt(index);
          debugPrint('❌ [_handleUpdate] Uklonio sam ${mergedRecord['putnik_ime']} iz _lastValue');
        } else {
          debugPrint('⚠️ [_handleUpdate] ${mergedRecord['putnik_ime']} se ne uključuje (aktivan=$aktivan, obrisan=$obrisan, isDuplicate=$isDuplicate)');
        }
      }

      _emitUpdate();
    } catch (e) {
      debugPrint('❌ [RegistrovaniPutnik] UPDATE error: $e');
    }
  }

  /// 🔊 Emit update u stream
  static void _emitUpdate() {
    if (_sharedController != null && !_sharedController!.isClosed) {
      // Debug: Log šta emitujemo
      debugPrint('📤 [_emitUpdate] POČINJEMO EMIT: ${_lastValue!.length} putnika');
      for (int i = 0; i < _lastValue!.length; i++) {
        final p = _lastValue![i];
        debugPrint('  📤 [$i] ${p.putnikIme}');
      }
      _sharedController!.add(List.from(_lastValue!));
    }
  }

  /// 🧹 Čisti singleton cache - pozovi kad treba resetovati sve
  static void clearRealtimeCache() {
    // Čisti Aktivni stream
    _sharedSubscription?.cancel();
    RealtimeManager.instance.unsubscribe('registrovani_putnici');
    _sharedSubscription = null;
    _sharedController?.close();
    _sharedController = null;
    _lastValue = null;

    // Čisti Svi stream
    _sharedSviSubscription?.cancel();
    RealtimeManager.instance.unsubscribe('registrovani_putnici_svi');
    _sharedSviSubscription = null;
    _sharedSviController?.close();
    _sharedSviController = null;
    _lastSviValue = null;
  }

  /// 📱 Normalizuje broj telefona za poređenje
  static String _normalizePhone(String telefon) {
    var cleaned = telefon.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+381')) {
      cleaned = '0${cleaned.substring(4)}';
    } else if (cleaned.startsWith('00381')) {
      cleaned = '0${cleaned.substring(5)}';
    }
    return cleaned;
  }

  /// 🔍 Proveri da li već postoji putnik sa istim brojem telefona
  /// ✅ FIX: Ignoriši duplikate i obrisane putnike
  Future<RegistrovaniPutnik?> findByPhone(String telefon) async {
    if (telefon.isEmpty) return null;

    final normalizedInput = _normalizePhone(telefon);

    // Dohvati samo ORIGINALNE (ne-duplicirane) putnike koji nisu obrisani
    final allPutnici =
        await _supabase.from('registrovani_putnici').select().eq('obrisan', false).eq('is_duplicate', false);

    for (final p in allPutnici) {
      final storedPhone = p['broj_telefona'] as String? ?? '';
      if (storedPhone.isNotEmpty && _normalizePhone(storedPhone) == normalizedInput) {
        return RegistrovaniPutnik.fromMap(p);
      }
    }
    return null;
  }

  /// Kreira novog mesečnog putnika
  /// Baca grešku ako već postoji putnik sa istim brojem telefona
  /// Baca grešku ako je kapacitet popunjen za bilo koji termin (osim ako je skipKapacitetCheck=true)
  Future<RegistrovaniPutnik> createRegistrovaniPutnik(
    RegistrovaniPutnik putnik, {
    bool skipKapacitetCheck = false,
  }) async {
    // 🔍 PROVERA DUPLIKATA - pre insert-a proveri da li već postoji
    final telefon = putnik.brojTelefona;
    if (telefon != null && telefon.isNotEmpty) {
      final existing = await findByPhone(telefon);
      if (existing != null) {
        throw Exception('Putnik sa ovim brojem telefona već postoji: ${existing.putnikIme}. '
            'Možete ga pronaći u listi putnika.');
      }
    }

    // 🚫 PROVERA KAPACITETA - Da li ima slobodnih mesta za sve termine?
    // Preskači ako admin uređuje (skipKapacitetCheck=true)
    final putnikMap = putnik.toMap();
    if (!skipKapacitetCheck) {
      final rawPolasci = putnikMap['polasci_po_danu'];
      Map<String, dynamic>? polasci;
      if (rawPolasci is Map) {
        polasci = Map<String, dynamic>.from(rawPolasci);
      }

      if (polasci != null) {
        await _validateKapacitetForRawPolasci(polasci, brojMesta: putnik.brojMesta, tipPutnika: putnik.tip);
      }
    }

    final response = await _supabase.from('registrovani_putnici').insert(putnikMap).select('''
          *
        ''').single();

    clearCache();

    return RegistrovaniPutnik.fromMap(response);
  }

  /// 🚫 Validira da ima slobodnih mesta za sve termine putnika
  /// Prima raw polasci_po_danu map iz baze (format: { "pon": { "bc": "8:00", "vs": null }, ... })
  Future<void> _validateKapacitetForRawPolasci(Map<String, dynamic> polasciPoDanu,
      {int brojMesta = 1, String? tipPutnika, String? excludeId}) async {
    if (polasciPoDanu.isEmpty) return;

    final danas = DateTime.now();
    final currentWeekday = danas.weekday;
    const daniMap = {'pon': 1, 'uto': 2, 'sre': 3, 'cet': 4, 'pet': 5, 'sub': 6, 'ned': 7};
    final daniKratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];

    // Proveri svaki dan koji putnik ima definisan
    for (final danKratica in daniKratice) {
      final danData = polasciPoDanu[danKratica];
      if (danData == null || danData is! Map) continue;

      final targetWeekday = daniMap[danKratica] ?? 1;

      // 🚫 PRESKOČI PROVERU ZA PRETHODNE DANE U NEDELJI (FIX korisničkog zahteva)
      // Ako je danas utorak, ne proveravaj ponedeljak jer je taj polazak već prošao
      // i admin ne želi da bude blokiran ako je juče bio pun bus.
      if (targetWeekday < currentWeekday) {
        continue;
      }

      // Proveri BC polazak - PAŽNJA: null.toString() = "null", ne prazan string!
      final bcValue = danData['bc'];
      final bcVreme = (bcValue != null && bcValue.toString().isNotEmpty && bcValue.toString() != 'null')
          ? bcValue.toString()
          : null;

      if (bcVreme != null) {
        // Izračunaj datum za ovaj dan u narednih 7 dana
        final targetDate = _getNextDateForDay(danas, danKratica);
        final datumStr = targetDate.toIso8601String().split('T')[0];

        final normalizedVreme = GradAdresaValidator.normalizeTime(bcVreme);
        final imaMesta = await SlobodnaMestaService.imaSlobodnihMesta('BC', normalizedVreme,
            datum: datumStr, tipPutnika: tipPutnika, brojMesta: brojMesta, excludeId: excludeId);
        if (!imaMesta) {
          final danPunoIme = _getDanPunoIme(danKratica);
          throw Exception(
            'NEMA SLOBODNIH MESTA!\n\n'
            'Termin: $danPunoIme u $bcVreme (Bela Crkva)\n'
            'Kapacitet je popunjen.\n\n'
            'Izaberite drugi termin ili kontaktirajte admina.',
          );
        }
      }

      // Proveri VS polazak - PAŽNJA: null.toString() = "null", ne prazan string!
      final vsValue = danData['vs'];
      final vsVreme = (vsValue != null && vsValue.toString().isNotEmpty && vsValue.toString() != 'null')
          ? vsValue.toString()
          : null;

      if (vsVreme != null) {
        final targetDate = _getNextDateForDay(danas, danKratica);
        final datumStr = targetDate.toIso8601String().split('T')[0];

        final normalizedVreme = GradAdresaValidator.normalizeTime(vsVreme);
        final imaMesta = await SlobodnaMestaService.imaSlobodnihMesta('VS', normalizedVreme,
            datum: datumStr, tipPutnika: tipPutnika, brojMesta: brojMesta, excludeId: excludeId);
        if (!imaMesta) {
          final danPunoIme = _getDanPunoIme(danKratica);
          throw Exception(
            'NEMA SLOBODNIH MESTA!\n\n'
            'Termin: $danPunoIme u $vsVreme (Vršac)\n'
            'Kapacitet je popunjen.\n\n'
            'Izaberite drugi termin ili kontaktirajte admina.',
          );
        }
      }
    }
  }

  /// Vraća sledeći datum za dati dan u nedelji
  DateTime _getNextDateForDay(DateTime fromDate, String danKratica) {
    const daniMap = {'pon': 1, 'uto': 2, 'sre': 3, 'cet': 4, 'pet': 5, 'sub': 6, 'ned': 7};
    final targetWeekday = daniMap[danKratica] ?? 1;
    final currentWeekday = fromDate.weekday;

    int daysToAdd = targetWeekday - currentWeekday;
    if (daysToAdd < 0) daysToAdd += 7;

    return fromDate.add(Duration(days: daysToAdd));
  }

  /// Vraća puno ime dana
  String _getDanPunoIme(String kratica) {
    const map = {
      'pon': 'Ponedeljak',
      'uto': 'Utorak',
      'sre': 'Sreda',
      'cet': 'Četvrtak',
      'pet': 'Petak',
      'sub': 'Subota',
      'ned': 'Nedelja',
    };
    return map[kratica] ?? kratica;
  }

  /// Ažurira mesečnog putnika
  /// Proverava kapacitet ako se menjaju termini (polasci_po_danu)
  Future<RegistrovaniPutnik> updateRegistrovaniPutnik(
    String id,
    Map<String, dynamic> updates, {
    bool skipKapacitetCheck = false,
  }) async {
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

    // 🛡️ MERGE SA POSTOJEĆIM MARKERIMA U BAZI (bc_pokupljeno, bc_placeno, itd.)
    if (updates.containsKey('polasci_po_danu')) {
      final noviPolasci = updates['polasci_po_danu'];
      if (noviPolasci != null && noviPolasci is Map) {
        // Čitaj trenutno stanje iz baze
        final trenutnoStanje =
            await _supabase.from('registrovani_putnici').select('polasci_po_danu').eq('id', id).limit(1).maybeSingle();

        if (trenutnoStanje == null) {
          debugPrint('🔴 [RegistrovaniPutnikService] Passenger not found: $id');
          throw Exception('Putnik sa ID-om $id nije pronađen');
        }

        final rawPolasciDB = trenutnoStanje['polasci_po_danu'];
        Map<String, dynamic>? trenutniPolasci;

        if (rawPolasciDB is String) {
          try {
            trenutniPolasci = jsonDecode(rawPolasciDB) as Map<String, dynamic>?;
          } catch (e) {
            debugPrint('Greška pri parsu polasci_po_danu stringa: $e');
          }
        } else if (rawPolasciDB is Map) {
          trenutniPolasci = Map<String, dynamic>.from(rawPolasciDB);
        }

        if (trenutniPolasci != null) {
          // Merge novi polasci sa postojećim markerima
          final mergedPolasci = <String, dynamic>{};

          // Kopiraj sve dane iz novih podataka
          noviPolasci.forEach((dan, noviPodaci) {
            if (noviPodaci is Map) {
              mergedPolasci[dan] = Map<String, dynamic>.from(noviPodaci);
            } else {
              mergedPolasci[dan] = noviPodaci;
            }
          });

          // Sačuvaj postojeće markere (pokupljeno, placeno, vozac) iz baze
          trenutniPolasci.forEach((dan, stariPodaci) {
            if (stariPodaci is Map && mergedPolasci.containsKey(dan)) {
              final danPolasci = mergedPolasci[dan] as Map<String, dynamic>;
              final stariDanPolasci = stariPodaci as Map<String, dynamic>;

              // Čuvaj vozačeve markere
              if (stariDanPolasci.containsKey('bc_pokupljeno')) {
                danPolasci['bc_pokupljeno'] = stariDanPolasci['bc_pokupljeno'];
              }
              if (stariDanPolasci.containsKey('bc_placeno')) {
                danPolasci['bc_placeno'] = stariDanPolasci['bc_placeno'];
              }
              if (stariDanPolasci.containsKey('vs_pokupljeno')) {
                danPolasci['vs_pokupljeno'] = stariDanPolasci['vs_pokupljeno'];
              }
              if (stariDanPolasci.containsKey('vs_placeno')) {
                danPolasci['vs_placeno'] = stariDanPolasci['vs_placeno'];
              }
              if (stariDanPolasci.containsKey('bc_pokupljeno_vozac')) {
                danPolasci['bc_pokupljeno_vozac'] = stariDanPolasci['bc_pokupljeno_vozac'];
              }
              if (stariDanPolasci.containsKey('vs_pokupljeno_vozac')) {
                danPolasci['vs_pokupljeno_vozac'] = stariDanPolasci['vs_pokupljeno_vozac'];
              }
            }
          });

          updates['polasci_po_danu'] = mergedPolasci;
        }
      }
    }

    // 🚫 PROVERA KAPACITETA - ako se menjaju termini
    if (!skipKapacitetCheck && updates.containsKey('polasci_po_danu')) {
      final polasciPoDanu = updates['polasci_po_danu'];
      if (polasciPoDanu != null && polasciPoDanu is Map) {
        // Dohvati broj_mesta i tip za proveru kapaciteta
        final currentData =
            await _supabase.from('registrovani_putnici').select('broj_mesta, tip').eq('id', id).limit(1).maybeSingle();

        if (currentData == null) {
          debugPrint('🔴 [RegistrovaniPutnikService] Passenger not found for capacity check: $id');
          throw Exception('Putnik sa ID-om $id nije pronađen za proveru kapaciteta');
        }
        final bm = updates['broj_mesta'] ?? currentData['broj_mesta'] ?? 1;
        final t = updates['tip'] ?? currentData['tip'];

        // Direktno koristi raw polasci_po_danu map za validaciju
        await _validateKapacitetForRawPolasci(Map<String, dynamic>.from(polasciPoDanu),
            brojMesta: bm is num ? bm.toInt() : 1, tipPutnika: t?.toString().toLowerCase(), excludeId: id);
      }
    }

    final response = await _supabase.from('registrovani_putnici').update(updates).eq('id', id).select('''
          *
        ''').single();

    clearCache();

    return RegistrovaniPutnik.fromMap(response);
  }

  /// Toggle aktivnost mesečnog putnika
  Future<bool> toggleAktivnost(String id, bool aktivnost) async {
    try {
      await _supabase.from('registrovani_putnici').update({
        'aktivan': aktivnost,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

      clearCache();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Ažurira mesečnog putnika (legacy metoda name)
  Future<RegistrovaniPutnik?> azurirajMesecnogPutnika(RegistrovaniPutnik putnik) async {
    try {
      final result = await updateRegistrovaniPutnik(putnik.id, putnik.toMap());
      return result;
    } catch (e) {
      rethrow; // Prebaci grešku da caller može da je uhvati
    }
  }

  /// Dodaje novog mesečnog putnika (legacy metoda name)
  Future<RegistrovaniPutnik> dodajMesecnogPutnika(
    RegistrovaniPutnik putnik, {
    bool skipKapacitetCheck = false,
  }) async {
    return await createRegistrovaniPutnik(putnik, skipKapacitetCheck: skipKapacitetCheck);
  }

  /// Ažurira plaćanje za mesec (vozacId je UUID)
  /// Koristi voznje_log za praćenje vožnji
  Future<bool> azurirajPlacanjeZaMesec(
    String putnikId,
    double iznos,
    String vozacIme, // 🔧 FIX: Sada prima IME vozača, ne UUID
    DateTime pocetakMeseca,
    DateTime krajMeseca,
  ) async {
    String? validVozacId;

    try {
      // Konvertuj ime vozača u UUID za foreign key kolonu
      if (vozacIme.isNotEmpty) {
        if (_isValidUuid(vozacIme)) {
          // Ako je već UUID, koristi ga
          validVozacId = vozacIme;
        } else {
          // Konvertuj ime u UUID
          try {
            await VozacMappingService.initialize();
            var converted = VozacMappingService.getVozacUuidSync(vozacIme);
            converted ??= await VozacMappingService.getVozacUuid(vozacIme);
            if (converted != null && _isValidUuid(converted)) {
              validVozacId = converted;
            }
          } catch (e) {
            debugPrint('❌ azurirajPlacanjeZaMesec: Greška pri VozacMapping za "$vozacIme": $e');
          }
        }
      }

      if (validVozacId == null) {
        debugPrint(
            '⚠️ azurirajPlacanjeZaMesec: vozacId je NULL za vozača "$vozacIme" - uplata neće biti u statistici!');
      }

      await VoznjeLogService.dodajUplatu(
        putnikId: putnikId,
        datum: DateTime.now(),
        iznos: iznos,
        vozacId: validVozacId,
        placeniMesec: pocetakMeseca.month,
        placenaGodina: pocetakMeseca.year,
        tipUplate: 'uplata_mesecna',
      );

      final now = DateTime.now();

      // ✅ Dohvati polasci_po_danu da bismo dodali plaćanje po danu
      final currentData = await _supabase
          .from('registrovani_putnici')
          .select('polasci_po_danu')
          .eq('id', putnikId)
          .limit(1)
          .maybeSingle();

      if (currentData == null) {
        debugPrint('🔴 [RegistrovaniPutnikService] Passenger not found for logging: $putnikId');
        return false;
      }

      // Odredi dan
      const daniKratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
      final danKratica = daniKratice[now.weekday - 1];

      // Parsiraj postojeći polasci_po_danu
      Map<String, dynamic> polasciPoDanu = {};
      final rawPolasci = currentData['polasci_po_danu'];
      if (rawPolasci != null) {
        if (rawPolasci is String) {
          try {
            polasciPoDanu = Map<String, dynamic>.from(jsonDecode(rawPolasci));
          } catch (_) {}
        } else if (rawPolasci is Map) {
          polasciPoDanu = Map<String, dynamic>.from(rawPolasci);
        }
      }

      // Ažuriraj dan sa plaćanjem - jednostavno polje placeno_vozac (važi za ceo mesec)
      final dayData = Map<String, dynamic>.from(polasciPoDanu[danKratica] as Map? ?? {});
      dayData['placeno'] = now.toIso8601String();
      dayData['placeno_vozac'] = vozacIme; // Jedno polje za vozača
      dayData['placeno_iznos'] = iznos;
      polasciPoDanu[danKratica] = dayData;

      // ✅ FIX: NE MENJAJ vozac_id pri plaćanju!
      // Naplata i dodeljivanje putnika vozaču su dve RAZLIČITE stvari.
      // vozac_id se menja SAMO kroz DodeliPutnike ekran.

      // 💰 PLAĆANJE: Direktan UPDATE bez provere kapaciteta
      // Plaćanje ne menja termine, samo dodaje informaciju o uplati u polasci_po_danu JSON
      await _supabase.from('registrovani_putnici').update({
        'polasci_po_danu': polasciPoDanu,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', putnikId);

      return true;
    } catch (e) {
      // 🔧 FIX: Baci exception sa pravom greškom da korisnik vidi šta je problem
      rethrow;
    }
  }

  /// Helper funkcija za validaciju UUID formata
  bool _isValidUuid(String str) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(str);
  }

  /// Briše mesečnog putnika (soft delete)
  Future<bool> obrisiRegistrovaniPutnik(String id) async {
    try {
      await _supabase.from('registrovani_putnici').update({
        'obrisan': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

      clearCache();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Traži mesečne putnike po imenu, prezimenu ili broju telefona
  Future<List<RegistrovaniPutnik>> searchregistrovaniPutnici(String query) async {
    final response = await _supabase
        .from('registrovani_putnici')
        .select('''
          *
        ''')
        .eq('obrisan', false)
        .or('lower(unaccent(putnik_ime)) ilike lower(unaccent(\'%$query%\')),lower(unaccent(broj_telefona)) ilike lower(unaccent(\'%$query%\'))')
        .order('putnik_ime');

    return response.map((json) => RegistrovaniPutnik.fromMap(json)).toList();
  }

  /// Dohvata sva plaćanja za mesečnog putnika
  /// 🔄 POJEDNOSTAVLJENO: Koristi voznje_log + registrovani_putnici
  Future<List<Map<String, dynamic>>> dohvatiPlacanjaZaPutnika(
    String putnikIme,
  ) async {
    try {
      List<Map<String, dynamic>> svaPlacanja = [];

      final putnik =
          await _supabase.from('registrovani_putnici').select('id, vozac_id').eq('putnik_ime', putnikIme).maybeSingle();

      if (putnik == null) return [];

      final placanjaIzLoga = await _supabase.from('voznje_log').select().eq('putnik_id', putnik['id']).inFilter(
          'tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna']).order('datum', ascending: false) as List<dynamic>;

      for (var placanje in placanjaIzLoga) {
        svaPlacanja.add({
          'cena': placanje['iznos'],
          'created_at': placanje['created_at'],
          'vozac_ime': await _getVozacImeByUuid(placanje['vozac_id'] as String?),
          'putnik_ime': putnikIme,
          'datum': placanje['datum'],
          'placeniMesec': placanje['placeni_mesec'],
          'placenaGodina': placanje['placena_godina'],
        });
      }

      return svaPlacanja;
    } catch (e) {
      return [];
    }
  }

  /// Dohvata sva plaćanja za mesečnog putnika po ID-u
  Future<List<Map<String, dynamic>>> dohvatiPlacanjaZaPutnikaById(String putnikId) async {
    try {
      final placanjaIzLoga = await _supabase.from('voznje_log').select().eq('putnik_id', putnikId).inFilter(
          'tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna']).order('datum', ascending: false) as List<dynamic>;

      List<Map<String, dynamic>> results = [];
      for (var placanje in placanjaIzLoga) {
        results.add({
          'cena': placanje['iznos'],
          'created_at': placanje['created_at'],
          // 'vozac_ime': await _getVozacImeByUuid(placanje['vozac_id'] as String?), // Preskočimo vozača za performanse ako nije potreban
          'datum': placanje['datum'],
          'placeniMesec': placanje['placeni_mesec'],
          'placenaGodina': placanje['placena_godina'],
        });
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  /// Helper funkcija za dobijanje imena vozača iz UUID-a
  Future<String?> _getVozacImeByUuid(String? vozacUuid) async {
    if (vozacUuid == null || vozacUuid.isEmpty) return null;

    try {
      final response = await _supabase.from('vozaci').select('ime').eq('id', vozacUuid).limit(1).maybeSingle();
      if (response == null) {
        return VozacMappingService.getVozacIme(vozacUuid);
      }
      return response['ime'] as String?;
    } catch (e) {
      return VozacMappingService.getVozacIme(vozacUuid);
    }
  }

  /// Dohvata zakupljene putnike za današnji dan
  /// 🔄 POJEDNOSTAVLJENO: Koristi registrovani_putnici direktno
  static Future<List<Map<String, dynamic>>> getZakupljenoDanas() async {
    try {
      final response = await supabase
          .from('registrovani_putnici')
          .select()
          .eq('status', 'zakupljeno')
          .eq('aktivan', true)
          .eq('obrisan', false)
          .order('putnik_ime');

      return response.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Stream za realtime ažuriranja mesečnih putnika
  /// Koristi direktan Supabase Realtime
  Stream<List<RegistrovaniPutnik>> get registrovaniPutniciStream {
    return streamAktivniRegistrovaniPutnici();
  }

  /// Izračunava broj putovanja iz voznje_log
  static Future<int> izracunajBrojPutovanjaIzIstorije(
    String mesecniPutnikId,
  ) async {
    try {
      final response =
          await supabase.from('voznje_log').select('datum').eq('putnik_id', mesecniPutnikId).eq('tip', 'voznja');

      final jedinstveniDatumi = <String>{};
      for (final red in response) {
        if (red['datum'] != null) {
          jedinstveniDatumi.add(red['datum'] as String);
        }
      }

      return jedinstveniDatumi.length;
    } catch (e) {
      return 0;
    }
  }

  /// Izračunava broj otkazivanja iz voznje_log
  static Future<int> izracunajBrojOtkazivanjaIzIstorije(
    String mesecniPutnikId,
  ) async {
    try {
      final response =
          await supabase.from('voznje_log').select('datum').eq('putnik_id', mesecniPutnikId).eq('tip', 'otkazivanje');

      final jedinstveniDatumi = <String>{};
      for (final red in response) {
        if (red['datum'] != null) {
          jedinstveniDatumi.add(red['datum'] as String);
        }
      }

      return jedinstveniDatumi.length;
    } catch (e) {
      return 0;
    }
  }

  // ==================== ENHANCED CAPABILITIES ====================

  static final Map<String, dynamic> _cache = {};

  static void clearCache() {
    _cache.clear();
  }

  /// 🔍 Dobija vozača iz poslednjeg plaćanja za mesečnog putnika
  /// Koristi direktan Supabase stream
  static Stream<String?> streamVozacPoslednjegPlacanja(String putnikId) {
    return streamAktivniRegistrovaniPutnici().map((putnici) {
      try {
        final putnik = putnici.where((p) => p.id == putnikId).firstOrNull;
        if (putnik == null) return null;
        final vozacId = putnik.vozacId;
        if (vozacId != null && vozacId.isNotEmpty) {
          return VozacMappingService.getVozacImeWithFallbackSync(vozacId);
        }
        return null;
      } catch (e) {
        return null;
      }
    });
  }

  /// 🔥 Stream poslednjeg plaćanja za putnika (iz voznje_log)
  /// Vraća Map sa 'vozac_ime', 'datum' i 'iznos'
  static Stream<Map<String, dynamic>?> streamPoslednjePlacanje(String putnikId) async* {
    try {
      final response = await supabase
          .from('voznje_log')
          .select('datum, vozac_id, iznos')
          .eq('putnik_id', putnikId)
          .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna'])
          .order('datum', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        yield null;
        return;
      }

      final vozacId = response['vozac_id'] as String?;
      final datum = response['datum'] as String?;
      final iznos = (response['iznos'] as num?)?.toDouble() ?? 0.0;
      String? vozacIme;
      if (vozacId != null && vozacId.isNotEmpty) {
        vozacIme = VozacMappingService.getVozacImeWithFallbackSync(vozacId);
      }

      yield {
        'vozac_ime': vozacIme,
        'datum': datum,
        'iznos': iznos,
      };
    } catch (e) {
      debugPrint('⚠️ Error yielding vozac info: $e');
      yield null;
    }
  }

  /// 💰 Dohvati UKUPNO plaćeno za putnika (svi uplate)
  static Future<double> dohvatiUkupnoPlaceno(String putnikId) async {
    try {
      final response = await supabase
          .from('voznje_log')
          .select('iznos')
          .eq('putnik_id', putnikId)
          .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna']);

      double ukupno = 0.0;
      for (final row in response) {
        ukupno += (row['iznos'] as num?)?.toDouble() ?? 0.0;
      }
      return ukupno;
    } catch (e) {
      debugPrint('⚠️ Error calculating total payment: $e');
      return 0.0;
    }
  }

  /// 🔧 SINGLETON STREAM za SVE mesečne putnike (uključujući neaktivne)
  static Stream<List<RegistrovaniPutnik>> streamSviRegistrovaniPutnici() {
    if (_sharedSviController != null && !_sharedSviController!.isClosed) {
      if (_lastSviValue != null) {
        Future.microtask(() {
          if (_sharedSviController != null && !_sharedSviController!.isClosed) {
            _sharedSviController!.add(_lastSviValue!);
          }
        });
      }
      return _sharedSviController!.stream;
    }

    _sharedSviController = StreamController<List<RegistrovaniPutnik>>.broadcast();

    _fetchAndEmitSvi(supabase);
    _setupRealtimeSubscriptionSvi(supabase);

    return _sharedSviController!.stream;
  }

  static Future<void> _fetchAndEmitSvi(SupabaseClient supabase) async {
    try {
      final data = await supabase
          .from('registrovani_putnici')
          .select()
          .eq('obrisan', false) // Samo ovo je razlika - ne filtriramo po 'aktivan'
          .order('putnik_ime');

      final putnici = data.map((json) => RegistrovaniPutnik.fromMap(json)).toList();
      _lastSviValue = putnici;

      if (_sharedSviController != null && !_sharedSviController!.isClosed) {
        _sharedSviController!.add(putnici);
      }
    } catch (_) {}
  }

  static void _setupRealtimeSubscriptionSvi(SupabaseClient supabase) {
    _sharedSviSubscription?.cancel();
    _sharedSviSubscription = RealtimeManager.instance.subscribe('registrovani_putnici_svi').listen((payload) {
      _fetchAndEmitSvi(supabase);
    });
  }

  /// Dodaje termin za registrovanog putnika (integracija sa PutnikService logikom)
  Future<void> dodajTerminZaPutnika(Putnik putnik, {bool skipKapacitetCheck = false}) async {
    try {
      // Validacije iz PutnikService.dodajPutnika
      if (putnik.mesecnaKarta != true) {
        throw Exception('Svi putnici moraju biti registrovani.');
      }

      if (putnik.dodeljenVozac == null ||
          putnik.dodeljenVozac!.isEmpty ||
          !VozacBoja.isValidDriver(putnik.dodeljenVozac)) {
        throw Exception('Neregistrovan vozač: ${putnik.dodeljenVozac}');
      }

      if (GradAdresaValidator.isCityBlocked(putnik.grad)) {
        throw Exception('Grad ${putnik.grad} nije dozvoljen.');
      }

      if (putnik.adresa != null &&
          putnik.adresa!.isNotEmpty &&
          !GradAdresaValidator.validateAdresaForCity(putnik.adresa, putnik.grad)) {
        throw Exception('Adresa ${putnik.adresa} nije validna za ${putnik.grad}.');
      }

      // Provera kapaciteta
      if (!skipKapacitetCheck) {
        final gradKey = GradAdresaValidator.isBelaCrkva(putnik.grad) ? 'BC' : 'VS';
        final polazakVremeNorm = GradAdresaValidator.normalizeTime(putnik.polazak);
        final datumZaProveru = putnik.datum ?? DateTime.now().toIso8601String().split('T')[0];
        final slobodnaMestaData = await SlobodnaMestaService.getSlobodnaMesta(datum: datumZaProveru);
        final listaZaGrad = slobodnaMestaData[gradKey];
        if (listaZaGrad != null) {
          for (final sm in listaZaGrad) {
            if (sm.vreme == polazakVremeNorm) {
              final dostupnoMesta = sm.maxMesta - sm.zauzetaMesta;
              if (putnik.brojMesta > dostupnoMesta) {
                throw Exception('Nema dovoljno mesta za ${putnik.polazak} (${putnik.grad}).');
              }
            }
          }
        }
      }

      // Proveri da li putnik postoji
      final existingPutnici = await _supabase
          .from('registrovani_putnici')
          .select('id, putnik_ime, aktivan, polasci_po_danu, radni_dani')
          .eq('putnik_ime', putnik.ime)
          .eq('aktivan', true);
      if (existingPutnici.isEmpty) {
        throw Exception('Putnik ${putnik.ime} ne postoji.');
      }

      final registrovaniPutnik = existingPutnici.first;
      final putnikId = registrovaniPutnik['id'] as String;

      // Parsiraj polasci_po_danu
      Map<String, dynamic> polasciPoDanu = {};
      final rawPolasciPoDanu = registrovaniPutnik['polasci_po_danu'];
      if (rawPolasciPoDanu != null) {
        if (rawPolasciPoDanu is String) {
          polasciPoDanu = jsonDecode(rawPolasciPoDanu) as Map<String, dynamic>;
        } else if (rawPolasciPoDanu is Map) {
          polasciPoDanu = Map<String, dynamic>.from(rawPolasciPoDanu);
        }
      }

      final danKratica = putnik.dan.toLowerCase();
      final gradKeyLower = GradAdresaValidator.isBelaCrkva(putnik.grad) ? 'bc' : 'vs';
      final polazakVreme = GradAdresaValidator.normalizeTime(putnik.polazak);

      if (!polasciPoDanu.containsKey(danKratica)) {
        polasciPoDanu[danKratica] = {'bc': null, 'vs': null};
      }
      final danPolasci = Map<String, dynamic>.from(polasciPoDanu[danKratica]);
      danPolasci[gradKeyLower] = polazakVreme;
      if (putnik.brojMesta > 1) {
        danPolasci['${gradKeyLower}_mesta'] = putnik.brojMesta;
      }
      if (putnik.adresaId != null) {
        danPolasci['${gradKeyLower}_adresa_danas_id'] = putnik.adresaId;
      }
      if (putnik.adresa != null && putnik.adresa!.isNotEmpty) {
        danPolasci['${gradKeyLower}_adresa_danas'] = putnik.adresa;
      }
      polasciPoDanu[danKratica] = danPolasci;

      // Ažuriraj radni_dani
      String radniDani = registrovaniPutnik['radni_dani'] ?? '';
      final radniDaniList = radniDani.split(',').map((d) => d.trim().toLowerCase()).toList();
      if (!radniDaniList.contains(danKratica)) {
        radniDaniList.add(danKratica);
        radniDani = radniDaniList.join(',');
      }

      // Update baza
      final updateData = {
        'polasci_po_danu': polasciPoDanu,
        'radni_dani': radniDani,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        // 'updated_by': putnik.dodeljenVozac, // Uklonjeno - kolona ne postoji u tabeli
      };
      await _supabase.from('registrovani_putnici').update(updateData).eq('id', putnikId);

      // Audit
      await UserAuditService().logUserChange(putnikId, 'add');
    } catch (e) {
      rethrow;
    }
  }

  /// Dodeli putnika vozaču za određeni pravac
  Future<void> dodelPutnikaVozacuZaPravac(
    String putnikId,
    String? noviVozac,
    String place, {
    String? vreme,
    String? selectedDan,
  }) async {
    try {
      // Validacija vozača
      if (noviVozac != null && !VozacBoja.isValidDriver(noviVozac)) {
        throw Exception(
          'Nevalidan vozac: "$noviVozac". Dozvoljeni: ${VozacBoja.validDrivers.join(", ")}',
        );
      }

      // Dohvati trenutne podatke putnika
      final response =
          await _supabase.from('registrovani_putnici').select('polasci_po_danu').eq('id', putnikId).single();

      // Odredi dan
      const daniKratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
      String danKratica;
      if (selectedDan != null && selectedDan.isNotEmpty) {
        final normalizedDan = selectedDan.toLowerCase().substring(0, 3);
        danKratica = daniKratice.contains(normalizedDan) ? normalizedDan : daniKratice[DateTime.now().weekday - 1];
      } else {
        danKratica = daniKratice[DateTime.now().weekday - 1];
      }

      // Učitaj postojeći polasci_po_danu JSON
      Map<String, dynamic> polasci = {};
      final polasciRaw = response['polasci_po_danu'];
      if (polasciRaw != null) {
        if (polasciRaw is String) {
          try {
            polasci = jsonDecode(polasciRaw) as Map<String, dynamic>;
          } catch (_) {}
        } else if (polasciRaw is Map) {
          polasci = Map<String, dynamic>.from(polasciRaw);
        }
      }

      // Dodaj/ažuriraj vozača za specifičan dan, pravac i vreme
      if (!polasci.containsKey(danKratica)) {
        polasci[danKratica] = <String, dynamic>{};
      }
      final dayData = polasci[danKratica] as Map<String, dynamic>;

      // Ključ uključuje vreme: 'bc_5:00_vozac' ili 'vs_14:00_vozac'
      String vozacKey;
      if (vreme != null && vreme.isNotEmpty) {
        final normalizedVreme = GradAdresaValidator.normalizeTime(vreme);
        if (normalizedVreme.isNotEmpty) {
          vozacKey = '${place}_${normalizedVreme}_vozac';
        } else {
          vozacKey = '${place}_vozac'; // fallback ako normalizacija ne uspe
        }
      } else {
        // Fallback na stari format (bez vremena) ako vreme nije prosleđeno
        vozacKey = '${place}_vozac';
      }

      if (noviVozac != null) {
        dayData[vozacKey] = noviVozac;
      } else {
        dayData.remove(vozacKey);
      }
      polasci[danKratica] = dayData;

      // Sačuvaj u bazu
      await _supabase.from('registrovani_putnici').update({
        'polasci_po_danu': jsonEncode(polasci), // ✅ Konvertuj Map u JSON string
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', putnikId);
    } catch (e) {
      throw Exception('Greška pri dodeljivanju vozača za pravac: $e');
    }
  }

  /// Označi putnika kao plaćenog
  Future<void> oznaciPlaceno(
    String id,
    double iznos,
    String currentDriver, {
    String? grad,
  }) async {
    if (currentDriver.isEmpty) {
      throw ArgumentError('Vozač mora biti specificiran.');
    }

    final response = await _supabase.from('registrovani_putnici').select().eq('id', id).maybeSingle();
    if (response == null) return;

    final now = DateTime.now();

    // Izračunaj place iz grad parametra
    final bool jeBC = grad?.toLowerCase().contains('bela') ?? true;
    final place = jeBC ? 'bc' : 'vs';

    Map<String, dynamic> polasciPoDanu = {};
    final rawPolasci = response['polasci_po_danu'];
    if (rawPolasci != null) {
      if (rawPolasci is String) {
        try {
          polasciPoDanu = jsonDecode(rawPolasci) as Map<String, dynamic>;
        } catch (_) {}
      } else if (rawPolasci is Map) {
        polasciPoDanu = Map<String, dynamic>.from(rawPolasci);
      }
    }

    // Ažuriraj dan sa plaćanjem
    const daniKratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
    final danKratica = daniKratice[now.weekday - 1];
    final dayData = Map<String, dynamic>.from(polasciPoDanu[danKratica] as Map? ?? {});
    dayData['${place}_placeno'] = now.toIso8601String();
    dayData['${place}_placeno_vozac'] = currentDriver;
    dayData['${place}_placeno_iznos'] = iznos;
    polasciPoDanu[danKratica] = dayData;

    await _supabase.from('registrovani_putnici').update({
      'polasci_po_danu': polasciPoDanu,
      'updated_at': now.toUtc().toIso8601String(),
    }).eq('id', id);

    // Loguj uplatu u voznje_log
    String? vozacId;
    try {
      vozacId = await VozacMappingService.getVozacUuid(currentDriver);
      if (vozacId == null && currentDriver == 'Ivan') {
        vozacId = '67ea0a22-689c-41b8-b576-5b27145e8e5e';
      }
    } catch (e) {
      if (currentDriver == 'Ivan') {
        vozacId = '67ea0a22-689c-41b8-b576-5b27145e8e5e';
      }
    }

    if (vozacId != null) {
      await VoznjeLogService.dodajUplatu(
        putnikId: id,
        datum: now,
        iznos: iznos,
        vozacId: vozacId,
        placeniMesec: now.month,
        placenaGodina: now.year,
        tipUplate: 'uplata_dnevna',
      );
    }

    // Audit
    await UserAuditService().logUserChange(id, 'payment');
  }

  /// Označi bolovanje ili godišnji
  Future<void> oznaciBolovanjeGodisnji(
    String id,
    String tipOdsustva,
    String currentDriver,
  ) async {
    final response = await _supabase.from('registrovani_putnici').select().eq('id', id).maybeSingle();
    if (response == null) return;

    String statusZaBazu = tipOdsustva.toLowerCase();
    if (statusZaBazu == 'godišnji') {
      statusZaBazu = 'godisnji';
    }

    // Log u dnevnik
    await VoznjeLogService.logGeneric(
      tip: statusZaBazu == 'radi' ? 'povratak_na_posao' : 'odsustvo',
      putnikId: id,
      vozacId: currentDriver == 'self' ? null : await VozacMappingService.getVozacUuid(currentDriver),
    );

    // Admin audit
    final currentUser = _supabase.auth.currentUser;
    await AdminAuditService.logAction(
      adminName: currentUser?.email ?? 'Unknown Admin',
      actionType: 'change_status',
      details: 'Putnik $id promenjen status u $statusZaBazu',
      metadata: {
        'putnik_id': id,
        'new_status': statusZaBazu,
        'old_status': response['status'],
      },
    );

    await _supabase.from('registrovani_putnici').update({
      'status': statusZaBazu,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Označi putnika kao pokupljenog
  Future<void> oznaciPokupljen(String id, String currentDriver, {String? grad, String? selectedDan}) async {
    if (currentDriver.isEmpty) {
      throw ArgumentError('Vozač mora biti specificiran.');
    }

    final response = await _supabase.from('registrovani_putnici').select().eq('id', id).maybeSingle();
    if (response == null) return;

    final now = DateTime.now();

    const daniKratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
    String danKratica;
    if (selectedDan != null && selectedDan.isNotEmpty) {
      final normalizedDan = selectedDan.toLowerCase().substring(0, 3);
      danKratica = daniKratice.contains(normalizedDan) ? normalizedDan : daniKratice[now.weekday - 1];
    } else {
      danKratica = daniKratice[now.weekday - 1];
    }

    final bool jeBC = grad?.toLowerCase().contains('bela') ?? true;
    final place = jeBC ? 'bc' : 'vs';

    Map<String, dynamic> polasciPoDanu = {};
    final rawPolasci = response['polasci_po_danu'];
    if (rawPolasci != null) {
      if (rawPolasci is String) {
        try {
          polasciPoDanu = jsonDecode(rawPolasci) as Map<String, dynamic>;
        } catch (_) {}
      } else if (rawPolasci is Map) {
        polasciPoDanu = Map<String, dynamic>.from(rawPolasci);
      }
    }

    final dayData = Map<String, dynamic>.from(polasciPoDanu[danKratica] as Map? ?? {});
    dayData['${place}_pokupljeno'] = now.toIso8601String();
    dayData['${place}_pokupljeno_vozac'] = currentDriver;
    polasciPoDanu[danKratica] = dayData;

    await _supabase.from('registrovani_putnici').update({
      'polasci_po_danu': polasciPoDanu,
      'updated_at': now.toUtc().toIso8601String(),
    }).eq('id', id);

    // Log to voznje_log
    final vozacUuid = VozacMappingService.getVozacUuidSync(currentDriver);
    final danas = now.toIso8601String().split('T')[0];
    try {
      await _supabase.from('voznje_log').insert({
        'putnik_id': id,
        'datum': danas,
        'tip': 'voznja',
        'iznos': 0,
        'vozac_id': vozacUuid,
        'broj_mesta': 1, // default
      });
    } catch (logError) {
      // Log insert not critical
    }
  }

  /// Otkazi putnika
  Future<void> otkaziPutnika(
    String id,
    String otkazaoVozac, {
    String? selectedVreme,
    String? selectedGrad,
    String? selectedDan,
  }) async {
    final response = await _supabase.from('registrovani_putnici').select().eq('id', id).maybeSingle();
    if (response == null) return;

    final now = DateTime.now();

    // 🔧 FIX: Use centralized DateUtils.getDayAbbreviation to handle diacritics properly
    String danKratica;
    if (selectedDan != null && selectedDan.isNotEmpty) {
      danKratica = DateUtils.getDayAbbreviation(selectedDan);
    } else {
      const daniKratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
      danKratica = daniKratice[now.weekday - 1];
    }

    String place = 'bc';
    final gradZaOtkazivanje = selectedGrad ?? response['grad'] as String? ?? '';
    if (gradZaOtkazivanje.toLowerCase().contains('vr') || gradZaOtkazivanje.toLowerCase().contains('vs')) {
      place = 'vs';
    }

    Map<String, dynamic> polasci = {};
    final polasciRaw = response['polasci_po_danu'];
    if (polasciRaw != null) {
      if (polasciRaw is String) {
        try {
          polasci = jsonDecode(polasciRaw) as Map<String, dynamic>;
        } catch (_) {}
      } else if (polasciRaw is Map) {
        polasci = Map<String, dynamic>.from(polasciRaw);
      }
    }

    if (!polasci.containsKey(danKratica)) {
      polasci[danKratica] = <String, dynamic>{};
    }
    final dayData = polasci[danKratica] as Map<String, dynamic>;
    dayData['${place}_otkazano'] = now.toIso8601String();
    dayData['${place}_otkazao_vozac'] = otkazaoVozac;
    polasci[danKratica] = dayData;

    await _supabase.from('registrovani_putnici').update({
      'polasci_po_danu': jsonEncode(polasci), // ✅ Konvertuj Map u JSON string
      'updated_at': now.toUtc().toIso8601String(),
    }).eq('id', id);

    // Log to voznje_log
    final vozacUuid = await VozacMappingService.getVozacUuid(otkazaoVozac);
    final danas = now.toIso8601String().split('T')[0];
    try {
      await _supabase.from('voznje_log').insert({
        'putnik_id': id,
        'datum': danas,
        'tip': 'otkazivanje',
        'iznos': 0,
        'vozac_id': vozacUuid,
      });
    } catch (logError) {
      // Log insert not critical
    }

    // Audit
    await UserAuditService().logUserChange(id, 'cancel');
  }

  /// Resetuj karticu putnika
  Future<void> resetPutnikCard(
    String imePutnika,
    String currentDriver, {
    String? selectedVreme,
    String? selectedGrad,
    String? targetDan,
  }) async {
    if (currentDriver.isEmpty) {
      throw Exception('Funkcija zahteva specificiranje vozaca');
    }

    final registrovaniList =
        await _supabase.from('registrovani_putnici').select().eq('putnik_ime', imePutnika).limit(1);

    if (registrovaniList.isNotEmpty) {
      final putnikData = registrovaniList.first;

      Map<String, dynamic> polasci = {};
      final polasciRaw = putnikData['polasci_po_danu'];
      if (polasciRaw != null) {
        if (polasciRaw is String) {
          try {
            polasci = jsonDecode(polasciRaw) as Map<String, dynamic>;
          } catch (_) {}
        } else if (polasciRaw is Map) {
          polasci = Map<String, dynamic>.from(polasciRaw);
        }
      }

      String place = 'bc';
      final gradZaReset = selectedGrad ?? '';
      if (gradZaReset.toLowerCase().contains('vr') || gradZaReset.toLowerCase().contains('vs')) {
        place = 'vs';
      }

      String danKratica;
      if (targetDan != null && targetDan.isNotEmpty) {
        danKratica = targetDan.toLowerCase();
      } else {
        final weekday = DateTime.now().weekday;
        const daniKratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        danKratica = daniKratice[weekday - 1];
      }

      Map<String, dynamic> dayData = {};
      if (polasci.containsKey(danKratica)) {
        final dayDataRaw = polasci[danKratica];
        if (dayDataRaw != null && dayDataRaw is Map) {
          dayData = Map<String, dynamic>.from(dayDataRaw);
        }
      }

      dayData.remove('${place}_otkazano');
      dayData.remove('${place}_otkazao_vozac');
      dayData.remove('${place}_pokupljeno');
      dayData.remove('${place}_pokupljeno_vozac');
      dayData.remove('${place}_placeno');
      dayData.remove('${place}_placeno_vozac');
      dayData.remove('${place}_placeno_iznos');
      dayData.remove('placeno');
      dayData.remove('placeno_iznos');
      dayData.remove('placeno_vozac');
      polasci[danKratica] = dayData;

      final currentUser = _supabase.auth.currentUser;
      await AdminAuditService.logAction(
        adminName: currentUser?.email ?? 'Unknown Admin',
        actionType: 'reset_putnik_card',
        details: 'Resetovan putnik $imePutnika sa odmora/statusa na "radi"',
        metadata: {
          'putnik_ime': imePutnika,
          'place': place,
          'dan': danKratica,
        },
      );

      // ✅ FIX: Sačuva original JSON kao string (polasciPoDanuOriginal će biti prepisana)
      final jsonString = jsonEncode(polasci);
      debugPrint('🔧 [resetPutnikCard] Ažuriram $imePutnika - polasci_po_danu: $jsonString');

      await _supabase.from('registrovani_putnici').update({
        'status': 'radi',
        'polasci_po_danu': jsonString, // ✅ Konvertuj Map u JSON string
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('putnik_ime', imePutnika);

      debugPrint('✅ [resetPutnikCard] Uspešno ažuriran $imePutnika');
    }
  }

  /// Ukloni iz termina
  Future<void> ukloniIzTermina(
    String id, {
    required String datum,
    required String vreme,
    required String grad,
  }) async {
    final response = await _supabase.from('registrovani_putnici').select('uklonjeni_termini').eq('id', id).single();

    List<dynamic> uklonjeni = [];
    if (response['uklonjeni_termini'] != null) {
      uklonjeni = List<dynamic>.from(response['uklonjeni_termini'] as List);
    }

    final normDatum = datum.split('T')[0];
    final normVreme = GradAdresaValidator.normalizeTime(vreme);

    final vecPostoji = uklonjeni.any((ut) {
      final utMap = ut as Map<String, dynamic>;
      final utVreme = GradAdresaValidator.normalizeTime(utMap['vreme']?.toString());
      final utDatum = utMap['datum']?.toString().split('T')[0];
      return utDatum == normDatum && utVreme == normVreme && utMap['grad'] == grad;
    });

    if (vecPostoji) return;

    uklonjeni.add({
      'datum': normDatum,
      'vreme': normVreme,
      'grad': grad,
    });

    await _supabase.from('registrovani_putnici').update({
      'uklonjeni_termini': uklonjeni,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }
}
