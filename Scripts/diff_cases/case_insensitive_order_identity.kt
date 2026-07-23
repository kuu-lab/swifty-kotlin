// SKIP-DIFF (DEBT-DIFF-005): kswiftc models CASE_INSENSITIVE_ORDER as a
// top-level kotlin.text property (STDLIB-TEXT-TYPE-004), but real Kotlin only
// exposes it as the String companion member String.CASE_INSENSITIVE_ORDER --
// there is no top-level kotlin.text.CASE_INSENSITIVE_ORDER to import, so
// kotlinc rejects this file outright ("unresolved reference"). Pre-existing
// synthetic-surface mismatch, unrelated to BUG-036's referential-identity fix
// (which this case still validates against kswiftc itself); tracked as
// BUG-154. See docs/diff-skip-inventory.md.
import kotlin.text.CASE_INSENSITIVE_ORDER

fun main() {
    val a = CASE_INSENSITIVE_ORDER
    val b = CASE_INSENSITIVE_ORDER
    println(a === b)
    println(CASE_INSENSITIVE_ORDER.compare("alpha", "ALPHA"))
    println(listOf("b", "A", "c", "a").sortedWith(CASE_INSENSITIVE_ORDER))
}
