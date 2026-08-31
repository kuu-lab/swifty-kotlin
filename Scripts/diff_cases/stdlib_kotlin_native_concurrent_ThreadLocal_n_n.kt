// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent.ThreadLocal is only available on Kotlin/Native targets.
import kotlin.native.concurrent.ThreadLocal

@ThreadLocal
var threadLocalValue = 0

fun constructThreadLocal(): Any? = ThreadLocal()
