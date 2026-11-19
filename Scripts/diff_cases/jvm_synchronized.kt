// DIFF_JVM
// Regression: the JVM stdlib manifest must inject the monitor bridge
// declarations (kotlin.jvm.internal.__jvmMonitorEnter/__jvmMonitorExit)
// consumed by the inlined `synchronized` body; without them consumer
// compiles fail with unresolved-function errors.

fun main() {
    val lock = Any()
    val total = synchronized(lock) {
        20 + 22
    }
    println(total)
    synchronized(lock) {
        println("again")
    }
}
