// KUU-2259: mirrors JetBrains/kotlin's kt45022.kt and checks the singleton call executes.
fun box(): String {
    X += 1
    return "OK"
}

object X {
    operator fun plusAssign(value: Any) = Unit
}

fun statefulBox(): String {
    Stateful += 1
    Stateful.plusAssign(1)
    val alias = Stateful
    alias += 1
    val counter = Counter()
    counter += 1
    return if (Stateful.calls == 3 && counter.calls == 1) "OK" else "FAIL:${Stateful.calls}:${counter.calls}"
}

object Stateful {
    var calls = 0
    operator fun plusAssign(value: Any) { calls++ }
}

class Counter {
    var calls = 0
    operator fun plusAssign(value: Int) { calls += value }
}

fun main() { println(box()); println(statefulBox()) }
