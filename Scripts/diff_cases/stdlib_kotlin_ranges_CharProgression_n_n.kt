import kotlin.ranges.CharProgression.Companion as CharProgressionFactory

fun companionValue(): CharProgression.Companion = CharProgression.Companion

fun main() {
    val implicit: CharProgression.Companion = CharProgression
    val explicit: CharProgression.Companion = CharProgression.Companion
    val imported: CharProgression.Companion = CharProgressionFactory
    println(implicit === explicit)
    println(explicit === imported)
    println(imported === companionValue())

    val ascending = implicit.fromClosedRange('a', 'g', 2)
    val descending = explicit.fromClosedRange('g', 'a', -2)
    val empty = imported.fromClosedRange('z', 'a', 1)
    println(ascending.toList())
    println(descending.toList())
    println(empty.toList())
    println(CharProgressionFactory.fromClosedRange('b', 'f', 2).toList())
}
