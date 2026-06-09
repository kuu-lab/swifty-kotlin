// STDLIB-TEXT-FN-101: CharSequence.toList() returns List<Char>.
// Registered for both String and CharSequence receivers (Kotlin declares it on
// CharSequence; both lower to the same kk_string_toList runtime entry).
fun stringToList(s: String): List<Char> = s.toList()
fun charSequenceToList(cs: CharSequence): List<Char> = cs.toList()
