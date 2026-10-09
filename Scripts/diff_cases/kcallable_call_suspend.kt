// KUU-1377: KCallable.callSuspend / callSuspendBy on a suspend function reference
import kotlin.reflect.full.*
import kotlinx.coroutines.*

suspend fun sf(x: Int): Int = x * 2

fun main() {
    runBlocking {
        println(::sf.callSuspend(5))
        println(::sf.callSuspendBy(mapOf(::sf.parameters[0] to 6)))
    }
}
