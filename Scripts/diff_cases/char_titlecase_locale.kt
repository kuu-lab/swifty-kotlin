// Char.isTitleCase and Char.titlecase(locale): kotlin.text coverage for KUU-1062.
fun main() {
    // Only Lt-category chars report true (ǅ ǈ ǋ ǲ and Greek composites).
    val checks = listOf('a', 'A', 'ǅ', 'Ǆ', 'ǆ', 'ǈ', 'ǋ', 'ǲ', 'ǳ', 'ﬀ', 'ŉ', '5', 'İ', ' ')
    println(checks.map { it.isTitleCase() })

    val us = java.util.Locale("en", "US")
    val tr = java.util.Locale("tr", "TR")
    val chars = listOf('a', 'ǆ', 'Ǆ', 'ǅ', 'ŉ', '+', 'ß', 'ﬀ', 'i', 'I', 'İ')
    println(chars.map { it.titlecase(us) })
    println(chars.map { it.titlecase(tr) })
}
