// KUU-4314: kotlin.internal compile-time-only annotations must resolve on the
// JVM lane. Only the annotations present in the real kotlin-stdlib.jar are
// exercised here; KsNoInline/KsSymbolName/NonStableParameterNames are
// KSwiftK-vendored declarations with no kotlinc reference.
// DIFF_JVM: KUU-4314 — the JVM lane resolves the annotations through the
// bundled stdlib declarations and must produce the same output.
@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@kotlin.internal.InlineOnly
inline fun inlineOnlyDoubled(x: Int): Int = x + x

@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
fun <@kotlin.internal.OnlyInputTypes T> firstOf(x: T, y: T): T = x

fun main() {
    println(inlineOnlyDoubled(21))
    println(firstOf("a", "b"))
}
