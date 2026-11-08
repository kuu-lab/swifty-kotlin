// DIFF_JVM
// KUU-4351: a non-null Nothing operand is a subtype of every operator
// parameter, so kotlinc keeps only uniquely-resolvable overloads — the
// unsigned receivers and Char's plus/compareTo accept it while signed and
// floating-point receivers are ambiguous. The accepted forms must compile
// and reach the runtime (where the Nothing call throws).
fun n(): Nothing = TODO()

fun main() {
    val results = mutableListOf<String>()
    fun attempt(name: String, block: () -> Any?) {
        try {
            results.add(name + "=ok:" + block())
        } catch (e: Throwable) {
            results.add(name + "=threw")
        }
    }
    attempt("charPlus") { 'a' + n() }
    attempt("uintPlus") { 1u + n() }
    attempt("ulongPlus") { 1uL + n() }
    attempt("charLt") { 'a' < n() }
    attempt("uintLt") { 1u < n() }
    attempt("stringPlus") { "x" + n() }
    println(results.joinToString(","))
}
