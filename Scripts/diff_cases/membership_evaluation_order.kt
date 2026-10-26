var order = ""

fun low(i: Int): Int { order += "L"; return i }
fun high(i: Int): Int { order += "H"; return i }
fun candidate(i: Int): Int { order += "X"; return i }
fun nullableCandidate(i: Int): Int? { order += "X"; return i }
fun values(): List<Int> { order += "C"; return listOf(1, 2, 3) }

class NullableContainer {
    operator fun contains(value: Int?): Boolean = value == 2
}

fun nullableContainer(): NullableContainer { order += "C"; return NullableContainer() }

fun report(label: String, result: Boolean) {
    println("$label=$result:$order")
    order = ""
}

fun main() {
    report("range", candidate(2) in low(1)..high(3))
    report("notIn", candidate(0) !in low(1)..high(3))
    report("downTo", candidate(2) in low(3) downTo high(1))
    report("until", candidate(2) in low(1) until high(3))
    report("reversed", candidate(2) in (low(1)..high(3)).reversed())
    report("collection", candidate(2) in values())
    report("nullable", nullableCandidate(2) in nullableContainer())
}
