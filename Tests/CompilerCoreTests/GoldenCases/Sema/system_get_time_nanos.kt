import kotlin.system.getTimeNanos

fun main() {
    val t1: Long = getTimeNanos()
    val t2: Long = getTimeNanos()
    println(t2 >= t1)
}
