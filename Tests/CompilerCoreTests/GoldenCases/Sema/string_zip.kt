// STDLIB-TEXT-FN-116: CharSequence.zip(other) / zip(other, transform)
// Registered for both String and CharSequence receivers; both resolve to the
// bundled Kotlin source implementation.
fun stringZip(s: String, other: CharSequence): List<Pair<Char, Char>> = s.zip(other)
fun charSequenceZip(cs: CharSequence, other: CharSequence): List<Pair<Char, Char>> = cs.zip(other)
fun stringZipTransform(s: String, other: CharSequence): List<String> = s.zip(other) { a, b -> "$a$b" }
