/// Transliterate Devanagari (Hindi) text to Roman/Latin script.
///
/// This allows the Hindi Vosk model to produce output readable
/// as Urdu/Roman-Urdu (e.g., "मैं ठीक हूँ" → "main theek hoon").
String devanagariToRoman(String text) {
  final buffer = StringBuffer();

  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    final mapped = _devanagariMap[char];

    if (mapped != null) {
      buffer.write(mapped);
    } else if (char.codeUnitAt(0) >= 0x0900 && char.codeUnitAt(0) <= 0x097F) {
      // Unknown Devanagari character — skip
    } else {
      buffer.write(char); // Keep spaces, punctuation, numbers, etc.
    }
  }

  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Devanagari → Roman mapping (ITRANS-like, optimized for Urdu readability)
const Map<String, String> _devanagariMap = {
  // Vowels
  'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee',
  'उ': 'u', 'ऊ': 'oo', 'ऋ': 'ri',
  'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au',

  // Vowel marks (matras)
  'ा': 'aa', 'ि': 'i', 'ी': 'ee',
  'ु': 'u', 'ू': 'oo', 'ृ': 'ri',
  'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au',

  // Halant (virama) — suppresses inherent vowel
  '्': '',

  // Anusvara & Visarga
  'ं': 'n', 'ँ': 'n', 'ः': 'h',

  // Consonants
  'क': 'ka', 'ख': 'kha', 'ग': 'ga', 'घ': 'gha', 'ङ': 'nga',
  'च': 'cha', 'छ': 'chha', 'ज': 'ja', 'झ': 'jha', 'ञ': 'nya',
  'ट': 'ta', 'ठ': 'tha', 'ड': 'da', 'ढ': 'dha', 'ण': 'na',
  'त': 'ta', 'थ': 'tha', 'द': 'da', 'ध': 'dha', 'न': 'na',
  'प': 'pa', 'फ': 'pha', 'ब': 'ba', 'भ': 'bha', 'म': 'ma',
  'य': 'ya', 'र': 'ra', 'ल': 'la', 'व': 'va',
  'श': 'sha', 'ष': 'sha', 'स': 'sa', 'ह': 'ha',

  // Nukta consonants (Urdu-origin sounds)
  'क़': 'qa', 'ख़': 'kha', 'ग़': 'gha',
  'ज़': 'za', 'ड़': 'da', 'ढ़': 'dha', 'फ़': 'fa',

  // Special
  'ॐ': 'om',

  // Devanagari digits → Arabic/Western digits
  '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
  '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
};
