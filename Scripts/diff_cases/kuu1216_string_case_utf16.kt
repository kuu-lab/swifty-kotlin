// KUU-1216: case conversion preserves NUL and isolated UTF-16 surrogates.
import java.util.Locale

fun main() {
    val us = Locale("en", "US")
    val samples = listOf(
        "", "\u0000", "\u0000Ab\u0000", "A\u0000\u0000b",
        "a\uD83Db", "\uDC00A\uD800", "\uD800\u0000\uDC00",
        "\uE800\uE000A", "ß\u0000İ", "ΟΣ\u0000ΟΣ", "ΟΣ\uD800ΟΣ",
        "😀a\u0000B😀", "AΣ\u0000B", "A\u0000Σ", "AΣ\uD800B", "A\uD800Σ"
    )
    for (s in samples) {
        println(s.uppercase().map { it.code })
        println(s.lowercase().map { it.code })
        println(s.uppercase(us).map { it.code })
        println(s.lowercase(us).map { it.code })
    }
    val tr = Locale("tr")
    println("I\u0000\u0307".lowercase(tr).map { it.code })
    println("I\uD800\u0307".lowercase(tr).map { it.code })
    println("I\u0307\u0000\uD800I\u0307".lowercase(tr).map { it.code })
    println("i\u0000\uDC00i".uppercase(tr).map { it.code })
    println("I\u0301\u0000I\u0301".lowercase(Locale("lt")).map { it.code })
    // Valid supplementary letters must remain paired through whole-string mapping.
    println("\uD801\uDC00\u0000\uD801\uDC28".lowercase().map { it.code })
    println("\uD801\uDC00\u0000\uD801\uDC28".uppercase(us).map { it.code })
}
