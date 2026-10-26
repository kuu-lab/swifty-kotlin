import kotlin.coroutines.*

fun main() {
    var failed = false
    val suspendValue: suspend () -> Unit = {}
    val suspendAsAny: Any = suspendValue
    val regularValue: () -> Unit = {}
    val regularAsAny: Any = regularValue

    if (suspendValue !is SuspendFunction0<Unit>) failed = true
    if (suspendAsAny !is SuspendFunction0<*>) failed = true
    if (suspendAsAny is SuspendFunction3<*, *, *, *>) failed = true
    if (regularAsAny is SuspendFunction0<*>) failed = true
    if (suspendAsAny is Function0<*>) failed = true

    println(if (failed) "FAIL" else "OK")
}
