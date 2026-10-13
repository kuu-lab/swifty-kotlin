// KUU-968: an unqualified `emit` call inside `flow { }` defined in a class
// declaring its own `emit` member must resolve to FlowCollector.emit rather
// than dispatching to the class member.
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking

class S {
    val log = mutableListOf<Int>()
    fun emit(v: Int) { log.add(v) }
    fun f() = flow {
        emit(1)
        emit(2)
    }
    fun withExplicitReceiver() = flow {
        this@S.emit(100)
        emit(3)
    }
}

var topLevelHit = false
fun emit(v: Int) {
    topLevelHit = true
}

fun topLevelFlow() = flow {
    emit(10)
    emit(20)
}

fun main() = runBlocking {
    val s = S()
    val collected = mutableListOf<Int>()
    s.f().collect { collected.add(it) }
    println("log: ${s.log}")
    println("collected: $collected")

    val collected2 = mutableListOf<Int>()
    s.withExplicitReceiver().collect { collected2.add(it) }
    println("log after explicit: ${s.log}")
    println("collected2: $collected2")

    val collectedTop = mutableListOf<Int>()
    topLevelFlow().collect { collectedTop.add(it) }
    println("topLevelHit: $topLevelHit")
    println("collectedTop: $collectedTop")
}
