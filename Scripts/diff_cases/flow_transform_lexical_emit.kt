// KUU-966: Flow.transform callbacks must dispatch to FlowCollector.emit
// without crashing (SIGSEGV) when an emit member class is in lexical scope.
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

class Emitter {
    var count = 0
    fun emit(v: Int) {
        count++
    }

    suspend fun transformValues() {
        flowOf(1, 2).transform<Int, Int> {
            emit(it)
        }.collect {
        }
    }

    suspend fun explicitReceiver() {
        flowOf(10, 20).transform<Int, Int> {
            this@Emitter.emit(it)
            emit(it)
        }.collect {
        }
    }
}

var topLevelHit = false
fun emit(v: Int) {
    topLevelHit = true
}

fun main() = runBlocking {
    val emitter = Emitter()
    emitter.transformValues()
    println("emitter count after transform: ${emitter.count}")

    var collected = 0
    flowOf(3, 4).transform<Int, Int> {
        emit(it)
    }.collect {
        collected++
    }
    println("collected: $collected")
    println("emitter count: ${emitter.count}")
    println("topLevelHit: $topLevelHit")

    emitter.explicitReceiver()
    println("emitter count after explicit: ${emitter.count}")
}
