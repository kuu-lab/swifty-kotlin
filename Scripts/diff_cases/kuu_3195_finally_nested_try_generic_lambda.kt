// KUU-3195 (JetBrains finally/kt4134.kt): try/finally with a nested
// try-catch inside finally, calling a generic lambda parameter on a String
// argument. The inlined erased-ABI adapter smeared the flat String aggregate
// across kk_string_to_flat's argument registers (SIGSEGV).
fun <T, R> io(s: R, a: (R) -> T): T {
    try { return a(s) }
    finally { try { s.toString() } catch(e: Exception) {} }
}
fun main() { println(io("OK") { it }) }
