// KUU-3221: an elvis `?:` as the last expression of a Unit-coerced lambda
// must still evaluate both operands' side effects (JetBrains
// unit/unitCoercionWithElvis.kt).
var result = "FAIL"
var result2 = "FAIL"
var result3 = "FAIL"

fun launch(x: () -> Unit) { x() }

fun box(): String {
    launch {
        "test".let { null } ?: run { result = "OK" }
    }
    return result
}

fun main() {
    println(box())
    var local = "FAIL2"
    launch {
        local.let { null } ?: run { local = "OK2" }
    }
    println(local)
    val x: String? = null
    launch {
        x ?: run { result2 = "OK3" }
    }
    println(result2)
    launch {
        val y: String? = "non-null"
        y ?: run { result3 = "WRONG" }
    }
    println(result3)
}
