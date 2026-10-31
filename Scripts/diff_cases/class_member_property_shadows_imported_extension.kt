import kotlin.time.*
import kotlin.time.Duration.Companion.nanoseconds

// KUU-3776: an unrelated member of the enclosing class must not hide an
// imported member extension during `recv.name` lookup.
class T(val nanoseconds: Long) {
    val duration: Duration get() = nanoseconds.nanoseconds
    val direct: Duration get() = 5L.nanoseconds
}

fun main() {
    println(T(5).duration)
    println(T(5).direct)
}
