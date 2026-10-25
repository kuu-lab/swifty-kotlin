// KUU-3232 / JetBrains unsignedTypes/kt47716.kt: a bare class-name expression
// denotes the companion object, so compound-expression results must keep the
// companion value type for postfix member lookup.
fun box(): String {
    val r =
        try {
            ULong
        } finally {
            UInt.MAX_VALUE
        }.MAX_VALUE
    return if (r == ULong.MAX_VALUE) "OK" else "FAIL"
}

fun main() {
    println(box())
    println(if ((try { ULong } finally { Unit }).MAX_VALUE == ULong.MAX_VALUE) "OK" else "FAIL")
    val c = try { ULong } finally { Unit }
    println(if (c.MAX_VALUE == ULong.MAX_VALUE) "OK" else "FAIL")
    val fromIf = if (true) ULong else ULong
    println(if (fromIf.MAX_VALUE == ULong.MAX_VALUE) "OK" else "FAIL")
    val fromWhen = when (true) { true -> ULong; else -> ULong }
    println(if (fromWhen.MAX_VALUE == ULong.MAX_VALUE) "OK" else "FAIL")
    println(if (run { ULong }.MAX_VALUE == ULong.MAX_VALUE) "OK" else "FAIL")
    println(if ((try { "OK" } finally { 1 }).length == 2) "OK" else "FAIL")
}
