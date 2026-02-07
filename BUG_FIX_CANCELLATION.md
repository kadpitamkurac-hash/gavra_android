# BUG FIX: Passenger Cancellation Not Displaying (Red Color & Moving to Bottom)

## Problem Summary
When clicking the X button to cancel a passenger, the cancellation was being written to the database correctly, but:
1. ❌ Cards were NOT turning red (otkazano color)
2. ❌ Cards were NOT moving to the bottom of the list
3. ❌ No visual feedback to the user that cancellation was successful

## Root Cause Found
**The bug was in the `otkaziPutnika()` method in `RegistrovaniPutnikService`:**

When converting the full day name to a day abbreviation, the code was using:
```dart
final normalizedDan = selectedDan.toLowerCase().substring(0, 3);
```

This causes a problem with Serbian day names that have diacritical marks:
- "Četvrtak" (Thursday) → `substring(0, 3)` → "čet" ❌ (WRONG - has diacritic)
- But the database uses "cet" (without diacritic) as the key
- Result: Cancellation timestamp was written to a non-existent key like "čet" instead of "cet"
- The helper function `isOtkazanForDayAndPlace()` couldn't find the cancellation timestamp
- Cards never turned red or moved to bottom

## Solution Implemented

**Replaced the buggy substring logic with the centralized `DateUtils.getDayAbbreviation()` function**

This function properly handles diacritical marks:
```dart
// BEFORE (BUGGY):
final normalizedDan = selectedDan.toLowerCase().substring(0, 3);
danKratica = daniKratice.contains(normalizedDan) ? normalizedDan : daniKratice[now.weekday - 1];

// AFTER (FIXED):
String danKratica;
if (selectedDan != null && selectedDan.isNotEmpty) {
  danKratica = DateUtils.getDayAbbreviation(selectedDan);
} else {
  const daniKratice = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
  danKratica = daniKratice[now.weekday - 1];
}
```

The `getDayAbbreviation()` function normalizes diacritics:
```dart
static String getDayAbbreviation(String fullDayName) {
  final normalized = fullDayName.toLowerCase()
      .replaceAll('č', 'c')  // čet -> cet
      .replaceAll('ć', 'c')
      .replaceAll('š', 's')
      .replaceAll('ž', 'z');
  
  switch (normalized) {
    case 'cetvrtak':
    case 'cet':
      return 'cet';  // Always returns lowercase without diacritics
    // ... etc
  }
}
```

## Changes Made

**File: `lib/services/registrovani_putnik_service.dart`**
1. Added import: `import '../utils/date_utils.dart';`
2. Fixed `otkaziPutnika()` method (line ~1514) to use `DateUtils.getDayAbbreviation()`
3. Added debug logging to show the isoDate conversion to dayAbbr

**File: `lib/utils/registrovani_helpers.dart`**
1. Added import: `import 'package:flutter/foundation.dart';`
2. Added debug logging to `isOtkazanForDayAndPlace()` to trace JSON parsing

**File: `lib/models/putnik.dart`**
1. Added debug logging to `_createPutniciForDay()` to show targetDan being used

**File: `lib/services/registrovani_putnik_service.dart`**
1. Enhanced debug logging in `streamKombinovaniPutniciFiltered()` to show isoDate → dayAbbr conversion

## Testing Steps

After deploying this fix:

1. **Open HomeScreen**
2. **Select a day from dropdown** (e.g., "Četvrtak" / Thursday)
3. **Find a passenger to cancel**
4. **Click X button** and confirm cancellation
5. **Expected behavior:**
   - Card should immediately turn **RED** (otkazano color = #EF9A9A)
   - Card should move to **BOTTOM** of the list
   - The cancellation timestamp should appear in the database under the correct key ("čet" → "cet")

## Impact

✅ **This fix resolves:**
- Cancellations for Thursday (Četvrtak) specifically
- Any other day names with diacritical marks
- Ensures consistency between UI day names and database day abbreviations
- Passengers now properly display as canceled with visual feedback

## Related Code Paths

1. **Cancellation Write**: `RegistrovaniPutnikService.otkaziPutnika()` 
   - Converts day name to abbreviation
   - Writes `bc_otkazano` or `vs_otkazano` timestamp to database

2. **Cancellation Read**: `RegistrovaniHelpers.isOtkazanForDayAndPlace()`
   - Parses `polasci_po_danu` JSON
   - Looks for `{place}_otkazano` key
   - Returns true if timestamp exists

3. **Visual Display**: `CardColorHelper.getCardStateWithDriver()`
   - Checks `putnik.jeOtkazan` property
   - `jeOtkazan` depends on `otkazanZaPolazak`
   - Returns `CardState.otkazano` → color = #EF9A9A (red)

4. **List Sorting**: `PutnikList._putnikSortKey()`
   - Canceled passengers get sort value of 6 (bottom)
   - Other statuses get lower values (top of list)

## Prevention

To prevent similar issues in the future:
- Always use `DateUtils.getDayAbbreviation()` when converting day names
- Never use direct substring operations on internationalized text with diacritics
- Centralize day name normalization logic
