import kotlin.native.concurrent.ThreadLocal

@ThreadLocal
var threadLocalValue = 0

fun constructThreadLocal(): Any? = ThreadLocal()
