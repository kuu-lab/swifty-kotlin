import kotlin.math.*

// KUU-2773: exp/asin/acos must match the JVM (fdlibm) down to the last bit.
fun main() {
    println(exp(1.0))
    println(exp(0.5))
    println(exp(-1.0))
    println(exp(10.0))
    println(asin(0.5))
    println(asin(-0.99))
    println(acos(0.5))
    println(acos(0.9))
    println(acos(-0.99))
}
