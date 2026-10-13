// DIFF_CANDIDATE_ONLY
// DIFF_EXPECT_STDOUT: 0, 7, true
import kotlin.native.concurrent.ThreadLocal

@ThreadLocal
var threadLocalValue = 0

fun constructThreadLocal(): Any? = ThreadLocal()

fun main() {
    val initialValue = threadLocalValue
    threadLocalValue = 7
    println("$initialValue, $threadLocalValue, ${constructThreadLocal() != null}")
}
