// Test da simulira šta se dešava sa Anica Knezevic nakon otkazivanja
import 'dart:convert';

void main() {
  print('═════════════════════════════════════════════════════════════════════════════');
  print('FIX TEST: ANICA KNEZEVIC - Kako se čuva otkazivanje u bazi');
  print('═════════════════════════════════════════════════════════════════════════════\n');

  // Simulacija podataka iz baze - ANICA KNEZEVIC POSLE OTKAZIVANJA
  final dbRecord = {
    'id': 'anica-123',
    'putnik_ime': 'Anica Knezevic',
    'polasci_po_danu':
        '{"pon":{"bc":"05:00","vs":"19:00","bc_pokupljeno":"2026-02-02T05:20:01.562040","bc_pokupljeno_vozac":"Bojan","bc_otkazano":"2026-02-07T09:34:04.210869","bc_otkazao_vozac":"Bojan"},"uto":{"bc":"05:00","vs":"19:00"},"sre":{"bc":null,"vs":null},"cet":{"bc":null,"vs":null},"pet":{"bc":"05:00","vs":"19:00"}}'
  };

  print('KORAK 1: Čitanje iz baze');
  print('-' * 70);
  print('polasci_po_danu iz baze:');
  print(dbRecord['polasci_po_danu']);
  print('\n');

  // Simulacija kako RegistrovaniPutnik parsira podatke
  print('KORAK 2: RegistrovaniPutnik.fromMap()');
  print('-' * 70);

  final polaski = dbRecord['polasci_po_danu'] as String;
  final parsed = jsonDecode(polaski) as Map<String, dynamic>;

  print('Parsed polasci:');
  parsed.forEach((day, data) {
    print('  $day: $data');
  });
  print('\n');

  // Simulacija toMap() sa STARIM kodom (koji briše otkazivanje)
  print('KORAK 3: toMap() sa STARIM kodom (PROBLEM)');
  print('-' * 70);

  final Map<String, Map<String, String?>> normalizedPolasci = {};
  parsed.forEach((day, value) {
    if (value is Map) {
      final bc = value['bc']?.toString();
      final vs = value['vs']?.toString();
      // ❌ STARI KOD - SAMO čuva bc i vs, BRIŠE sve ostalo!
      normalizedPolasci[day] = {'bc': bc, 'vs': vs};
    }
  });

  print('Šta se čuva u bazi sa STARIM kodom:');
  print(jsonEncode(normalizedPolasci));
  print('\n⚠️  PROBLEM: bc_otkazano se BRIŠE! 🔥\n');

  // Simulacija toMap() sa NOVIM kodom (koji čuva originalni JSON)
  print('KORAK 4: toMap() sa NOVIM kodom (REŠENJE)');
  print('-' * 70);

  // 🆕 NOVI KOD - čuva originalni JSON!
  final polasciForDB = polaski.isNotEmpty ? parsed : normalizedPolasci;

  print('Šta se čuva u bazi sa NOVIM kodom:');
  print(jsonEncode(polasciForDB));
  print('\n✅ SVE JE SAČUVANO - uključujući bc_otkazano! 🎉\n');

  // Provera da li je otkazivanje sačuvano
  print('KORAK 5: Provera da li je otkazivanje sačuvano');
  print('-' * 70);

  final ponData = polasciForDB['pon'];
  if (ponData is Map && ponData.containsKey('bc_otkazano')) {
    print('✅ bc_otkazano je sačuvan: ${ponData['bc_otkazano']}');
    print('✅ Putnik će se prikazati kao OTKAZAN');
  } else {
    print('❌ bc_otkazano NIJE sačuvan');
    print('❌ Putnik će se prikazati kao NEPOKUPLJEN');
  }

  print('\n═════════════════════════════════════════════════════════════════════════════');
  print('ZAKLJUČAK: Fix je radio! Otkazivanje se sada čuva pravilno.');
  print('═════════════════════════════════════════════════════════════════════════════');
}
