// STDLIB-TEXT-FN-116: CharSequence.zip(other) / zip(other, transform)
// Registered for both String and CharSequence receivers.  Both lower to the
// same kk_string_zip / kk_string_zipTransform runtime entries.
fun stringZip(s: String, other: CharSequence): List<Pair<Char, Char>> = s.zip(other)
fun charSequenceZip(cs: CharSequence, other: CharSequence): List<Pair<Char, Char>> = cs.zip(other)
fun stringZipTransform(s: String, other: CharSequence): List<String> = s.zip(other) { a, b -> "$a$b" }
