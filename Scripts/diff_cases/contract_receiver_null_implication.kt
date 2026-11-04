// KUU-4041: `returns(false) implies (this != null)` receiver contracts must
// smart-cast the extension receiver to non-null on the matching branch.
// Covers bundled stdlib isNullOrEmpty/isNullOrBlank on CharSequence?,
// Collection<T>?, and Map<K,V>?, plus a user-declared `this@fn` contract.
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

@OptIn(ExperimentalContracts::class)
fun CharSequence?.isNullish(): Boolean {
    contract { returns(false) implies (this@isNullish != null) }
    return this == null
}

fun len(s: String?): Int {
    if (s.isNullOrEmpty()) return 0
    return s.length
}

fun main() {
    println(len("abc"))
    println(len(null))
    println(len(""))

    val t: String? = "x"
    if (!t.isNullOrBlank())
        println(t.length)

    // `||`/`&&` thread the false-outcome of the call into the RHS operand.
    val u: String? = "abcde"
    if (u.isNullOrEmpty() || u.length >= 5)
        println("or-branch")
    if (!u.isNullOrBlank() && u.length >= 5)
        println("and-branch")

    if (t.isNullish()) println("nullish") else println(t.length)

    // The same receiver contract already declared on the bundled
    // Collection<T>?.isNullOrEmpty / Map<K,V>?.isNullOrEmpty.
    val c: List<Int>? = listOf(1)
    if (!c.isNullOrEmpty()) println(c.size)
    val m: Map<String, Int>? = mapOf("a" to 1)
    if (!m.isNullOrEmpty()) println(m.size)
}
