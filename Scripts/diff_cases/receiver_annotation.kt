// DIFF_JVM
@Target(AnnotationTarget.VALUE_PARAMETER)
@Retention(AnnotationRetention.RUNTIME)
annotation class Marker

fun @receiver:Marker String.head(): Char = this[0]
fun main() { println("ok".head()) }
