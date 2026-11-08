// Nullable implicit receivers still resolve extensions whose declared
// receiver nullability they satisfy, and Any? members stay callable
// (KUU-4501). Pairs with kuu_4501_nullable_implicit_receiver_reject.kt.
fun String.firstCode(): Int = get(0).code
fun String?.safeCode(): Int = if (this == null) -1 else 2

fun viaNonNull(): Int = with("ab") { firstCode() }
fun viaNullableExt(): Int = with(null as String?) { safeCode() }
fun viaEquals(s: String?): Boolean = with(s) { equals("x") }
fun viaSmartCast(s: String?): Int {
    if (s != null) return with(s) { firstCode() }
    return -1
}
fun viaSafeCall(s: String?): Int = s?.firstCode() ?: -1
fun String.outer(): Int = with(null as String?) { firstCode() }

fun main() {
    println(viaNonNull())
    println(viaNullableExt())
    println(viaEquals("x"))
    println(viaSmartCast("ab"))
    println(viaSmartCast(null))
    println(viaSafeCall("ab"))
    println(viaSafeCall(null))
    println("L".outer())
}
