// A `;` inside a branch lambda of a property-initializer `when` must not end
// the when entry.
fun pick(mode: Int): String {
    var calls = ""
    val r = when (mode) {
        0 -> run { calls += "a"; "zero" }
        1 -> run { calls += "b"; calls += "c"; "one" }
        else -> "other"
    }
    val s = when {
        mode > 0 -> run { calls += "d"; "pos" }
        else -> "nonpos"
    }
    return "$r:$s:$calls"
}

fun main() {
    println(pick(0))
    println(pick(1))
    println(pick(2))
}
