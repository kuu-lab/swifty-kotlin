fun interface Action { fun run(): String }
fun interface Other { fun run(): String }
fun interface CallableAction : () -> String
fun interface SuspendedAction { suspend fun run(): String }
fun interface SuspendedCallableAction : suspend () -> String

fun target(): String = "ok"
suspend fun suspendTarget(): String = "ok"
fun action(f: Action): Any = f
fun other(f: Other): Any = f
fun callable(f: CallableAction): Any = f
fun suspended(f: SuspendedAction): Any = f
fun suspendedCallable(f: SuspendedCallableAction): Any = f

fun main() {
    val sam = action(::target)
    val same = action(::target)
    val different = other(::target)
    val raw: Any = ::target
    val directLambda: Any = { "ok" }
    val lambdaSam = action { "ok" }
    val functionSam = callable(::target)
    println(sam is Function0<*>)
    println(sam is Action)
    println(sam is Other)
    println(raw is Function0<*>)
    println(raw is Action)
    println(directLambda is Function0<*>)
    println(lambdaSam is Function0<*>)
    println(lambdaSam is Action)
    println(functionSam is Function0<*>)
    println(functionSam is CallableAction)
    println(sam == same)
    println(sam.hashCode() == same.hashCode())
    println(sam == different)
    println(sam == raw)
    val suspendSam = suspended(::suspendTarget)
    val suspendFunctionSam = suspendedCallable(::suspendTarget)
    val suspendRef: Any = ::suspendTarget
    println(suspendSam is Function1<*, *>)
    println(suspendSam is SuspendedAction)
    println(suspendFunctionSam is Function1<*, *>)
    println(suspendFunctionSam is SuspendedCallableAction)
    println(suspendRef is Function1<*, *>)
}
