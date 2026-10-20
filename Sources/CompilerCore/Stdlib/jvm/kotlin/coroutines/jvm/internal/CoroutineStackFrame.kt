package kotlin.coroutines.jvm.internal
interface CoroutineStackFrame {
    val callerFrame: CoroutineStackFrame?
    fun getStackTraceElement(): java.lang.StackTraceElement?
}
