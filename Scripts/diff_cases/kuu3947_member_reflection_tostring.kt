// DIFF_CANDIDATE_ONLY
// KUU-3947: KClass.memberProperties / memberFunctions / members handles are
// accessor-backed callable wrappers that must render JVM-style
// `val|fun pkg.Owner.name(P): kotlin.T` signatures, not `<object 0x…>`.
// Candidate-only: JVM kotlin-reflect needs `kotlin.reflect.full` imports and
// returns a different member set (java.lang members, inherited members), so
// byte parity is only pinnable on the candidate side.

class Named(val value: Int, var mutable: String, val list: List<Int>) {
    fun method(x: Int): Int = x
}

fun main() {
    for (m in Named::class.memberProperties) println("MP: $m")
    for (m in Named::class.memberFunctions) println("MF: $m")
    for (m in Named::class.members) println("M: $m")
    for (m in String::class.memberProperties) println("SMP: $m")
    for (m in String::class.memberFunctions) println("SMF: $m")
    for (m in IntArray::class.memberProperties) println("AMP: $m")
    for (m in UInt::class.memberProperties) println("UMP: $m")
}
