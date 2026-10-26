// KUU-3555: direct object-member imports must stay writable in compound assignments.
import Host.x

object Host { var x: Int = 0 }

fun main() {
    x += 1
    println(x++)
    println(++x)
    println(x)
}
