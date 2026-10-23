// DIFF_JVM
package diff

fun main() {
    val direct: IntRange = IntRange.EMPTY
    val explicit: IntRange = IntRange.Companion.EMPTY
    val companion: IntRange.Companion = IntRange.Companion
    println(direct.isEmpty())
    println(explicit.isEmpty())
    println(companion.EMPTY.isEmpty())
}
