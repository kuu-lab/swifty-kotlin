// Based on JetBrains/Kotlin's customCompareTo.kt at commit 679366a83f99851b42f64795f10ed803ff011c73.
var longCompareToInvocations = 0
var doubleCompareToInvocations = 0

private operator fun Long?.compareTo(other: Long?): Int {
    longCompareToInvocations++
    val diff = (this ?: 0L) - (other ?: 0L)
    return when {
        diff < 0L -> -1
        diff > 0L -> 1
        else -> 0
    }
}

private operator fun Double?.compareTo(other: Double?): Int {
    doubleCompareToInvocations++
    val diff = (this ?: 0.0) - (other ?: 0.0)
    return when {
        diff < 0.0 -> -1
        diff > 0.0 -> 1
        else -> 0
    }
}

fun checkLong(): String? {
    val a: Long? = null
    val b: Long? = 42L

    if (a > b) return "Fail Long >"
    if (a >= b) return "Fail Long >="
    if (!(a < b)) return "Fail Long <"
    if (!(a <= b)) return "Fail Long <="

    if (longCompareToInvocations != 4) return "Fail: expected 4 compareTo invocations, but was $longCompareToInvocations"
    return null
}

fun checkDouble(): String? {
    val a: Double? = null
    val b: Double? = 3.14

    if (a > b) return "Fail Double >"
    if (a >= b) return "Fail Double >="
    if (!(a < b)) return "Fail Double <"
    if (!(a <= b)) return "Fail Double <="

    if (doubleCompareToInvocations != 4) return "Fail: expected 4 compareTo invocations, but was $doubleCompareToInvocations"
    return null
}

fun box(): String {
    checkLong()?.let { return it }
    checkDouble()?.let { return it }
    return "OK"
}

fun minimalNullableLongCompare(): String {
    longCompareToInvocations = 0
    val a: Long? = null
    val b: Long? = 42L
    val result = a < b
    return "$result:$longCompareToInvocations"
}

var namedCompareInvocations = 0
fun Long?.compareCustom(other: Long?): Int {
    namedCompareInvocations++
    return ((this ?: 0L) - (other ?: 0L)).compareTo(0L)
}

fun namedExtensionControl(): String {
    namedCompareInvocations = 0
    val result = (null as Long?).compareCustom(42L)
    return "$result:$namedCompareInvocations"
}

var nominalCompareInvocations = 0
class NominalValue(val value: Int) {
    operator fun compareTo(other: NominalValue): Int {
        nominalCompareInvocations++
        return value - other.value
    }
}

fun nominalClassControl(): String {
    nominalCompareInvocations = 0
    val result = NominalValue(1) < NominalValue(2)
    return "$result:$nominalCompareInvocations"
}

fun builtinPrimitiveControl(): Boolean = 1L < 2L && 1.0 <= 2.0

fun main() {
    println(box())
    println(minimalNullableLongCompare())
    println(namedExtensionControl())
    println(nominalClassControl())
    println(builtinPrimitiveControl())
}
