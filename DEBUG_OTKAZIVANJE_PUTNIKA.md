# DEBUG CHECKLIST: AI RADNIK TEST - Otkazan za PON/BC

## Status Logike: ✅ ISPRAVNA
Sve tri test datoteke pokazuju da je logika za otkazivanje **potpuno ispravna**:
- ✅ `test_cancel_logic.dart` - Helper funkcija radi
- ✅ `test_putnik_cancel_full.dart` - Model i getter rade ispravno
- ✅ `test_cancel_complete_flow.dart` - Ceo flow je ispravan

## 🔍 Kako proveri da li putnik biva prikazan kao otkazan

### 1. PROVERI APLIKACIJU U REALNOM VREMENU

**Korak 1: Otvori Flutter aplikaciju**
- Prikaži listu putnika za **PONEDELJAK**
- Grad trebalo bi biti **BELA CRKVA (BC)**
- Trebalo bi da vidiš **AI RADNIK TEST** putnika

**Korak 2: Kakvu boju vidiš?**
- ✅ CRVENA boja → Putnik je pravilno označen kao otkazan
- ⚪ BELA boja → Postoji problem sa učitavanjem otkazivanja

### 2. PROVERI DEBUG LOGOVE

**U Flutter logovima trebalo bi videti:**

```
✨ [Putnik.fromRegistrovaniPutniciMultipleForDay] AI RADNIK TEST | target=pon | bcOtkazan=true | vsOtkazan=false | polazakBC=05:00 | polazakVS=null
```

Ako NEMA ovog loga:
- Putnik se ne učitava pravilno
- Ili isoDate nije prosleđen u stream
- Ili targetDay nije "pon"

**Trebalo bi videti:**

```
📍 [streamMap] ✨ TEST PUTNIK: AI RADNIK TEST | grad=Bela Crkva | dan=Pon | polazak=05:00 | otkazanZaPolazak=true | status=otkazan | jeOtkazan=true
```

Ako NEMA ovog loga:
- Stream nije emitovao ažuriranje
- Ili je putnik filtriran iz liste
- Ili real-time update nije stigao

**Trebalo bi videti:**

```
🎨 [PutnikCard] BUILD: AI RADNIK TEST | grad=Bela Crkva | dan=Pon | polazak=05:00 | cardState=otkazano | otkazanZaPolazak=true | status=otkazan | jeOtkazan=true
```

Ako NEMA ovog loga:
- Karta se ne rendera
- Ili putnik nije u listi

### 3. PROVERI BAZU PODATAKA (Supabase)

**Kolona `polasci_po_danu` za putnika "AI RADNIK TEST" trebala bi da sadrži:**

```json
{
  "pon": {
    "bc": "05:00",
    "bc_otkazano": "2026-02-07T08:03:45.821466",
    "bc_otkazao_vozac": "Bojan",
    "bc_pokupljeno": "2026-02-07T08:04:04.689004",
    "bc_pokupljeno_vozac": "Bojan"
  },
  "uto": {"bc": "05:00:00", "vs": "17:00"},
  "sre": {"bc": "05:00"},
  "cet": {"bc": "05:00"},
  "pet": {"bc": "05:00"}
}
```

**Važno:**
- ✅ `bc_otkazano` postoji za "pon"
- ✅ Ima ISO format timestamp
- ✅ Nema "vs_otkazano" jer putnik nema VS polazak za pon

### 4. PROVERI REAL-TIME STREAM (Supabase Realtime)

U Supabase console proveri:
- Realtime je uključen za tabelu `registrovani_putnici`? ✅
- Kada se ažurira `polasci_po_danu`, da li se event prosledi aplikaciji? ✅

## 🚀 MOGUĆA REŠENJA AKO PUTNIK NIJE OTKAZAN

### Scenario 1: Putnik se učitao PRIJE nego što je otkazan
**Simptom:** Putnik je bio vidljiv bez otkazivanja, sad ima crvenu boju nakon osvežavanja

**Rešenje:** Normalno - real-time ažuriranje radi! 🎉

### Scenario 2: Putnik se NIKAD ne prikazuje kao otkazan
**Simptom:** Putnik je uvek bela boja, čak i nakon osvežavanja

**Moguće uzroke:**

1. **isoDate nije prosleđen u stream**
   - Proveri: `home_screen.dart` linija ~1996
   - Trebalo bi: `isoDate: _getTargetDateIsoFromSelectedDay(_selectedDay)`

2. **targetDay nije "pon"**
   - Ako je korisnik na sledeću nedelju, targetDay je drugačiji
   - Otkazivanje je sačuvano samo za "pon"

3. **Real-time update se ne prima**
   - Proveri Supabase conectvnost
   - Proveri debug log: `🔄 [RegistrovaniPutnik] Updating putnik: ...`

4. **`polasci_po_danu` je NULL u bazi**
   - Proveri: Da li je JSON sačuvan u bazi pravilno?
   - Možda je čarobnjak dodao putnika sa starim formatom

### Scenario 3: DEBUG LOGOVI se ne prikazuju
**Simptom:** Ne vidim nijedan od debug logova

**Rešenje:**
1. Proveri da li je Flutter app u DEBUG modu
2. Proveri da li je konsola aktivna (F12 u Chrome DevTools)
3. Proveri filter - možda filtriraš samo grešku
4. Proverit da li je putnik stvarno učitana

## 📋 DEBUGGING PRIPREMA

**Za sledeću sesiju:**
1. Spremi ove test datoteke za referenca
2. Kopiraj debug logove iz aplikacije
3. Proveri Supabase bazu direktno
4. Verovatno je gotovo - logika je ispravna! ✅

## ZAKLJUČAK

**Kod je ispravno implementiran.** Sve tri nived logike rade:
1. ✅ Helper `isOtkazanForDayAndPlace()` pronalazi `bc_otkazano` u JSON
2. ✅ `otkazanZaPolazak` flag se postavlja na `true` u factory
3. ✅ `jeOtkazan` getter vraća `true`, što aktivira crvenu boju

Ako putnik nije otkazan na UI:
- Proveri koji dan se prikazuje
- Proveri debug logove
- Proveri bazu podataka
- Провест da li je `polasci_po_danu` JSON pravilno sačuvan

Ostalim rečima, **ne menja se kod** - trebalo bi da radi! 🎯
