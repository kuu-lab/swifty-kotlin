// DIFF_CANDIDATE_ONLY
// DIFF_EXPECT_OUTPUT: OK
import kotlin.coroutines.*

class Suspend0 : suspend () -> Unit {
    override suspend fun invoke() {}
}

interface Suspend1 : suspend (Int) -> Unit
fun interface Suspend0Sam : suspend () -> Unit
interface Suspend1And2 : suspend (Int) -> Unit, suspend (Int, Int) -> Unit

fun main() {
    var failed = false
    val classValue: Any = Suspend0()
    val interfaceValue: Any = object : Suspend1 {
        override suspend fun invoke(value: Int) {}
    }
    val funInterfaceValue: Any = Suspend0Sam {}
    val multipleAritiesValue: Any = object : Suspend1And2 {
        override suspend fun invoke(value: Int) {}
        override suspend fun invoke(first: Int, second: Int) {}
    }

    if (classValue !is SuspendFunction0<*>) failed = true
    if (classValue is SuspendFunction1<*, *>) failed = true
    if (interfaceValue !is SuspendFunction1<*, *>) failed = true
    if (interfaceValue is SuspendFunction0<*>) failed = true
    if (funInterfaceValue !is SuspendFunction0<*>) failed = true
    if (funInterfaceValue is SuspendFunction1<*, *>) failed = true
    if (multipleAritiesValue !is SuspendFunction1<*, *>) failed = true
    if (multipleAritiesValue !is SuspendFunction2<*, *, *>) failed = true
    if (multipleAritiesValue is SuspendFunction3<*, *, *, *>) failed = true

    println(if (failed) "FAIL" else "OK")
}
