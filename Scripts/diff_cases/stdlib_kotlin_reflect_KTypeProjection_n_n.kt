import kotlin.reflect.KTypeProjection
import kotlin.reflect.KVariance
import kotlin.reflect.typeOf

fun main() {
    KTypeProjection(null, null)
    KTypeProjection(KVariance.IN, typeOf<String>())
    val first: Any = KTypeProjection.Companion
    val second: Any = KTypeProjection.Companion
    println(first === second)

    try {
        KTypeProjection(KVariance.IN, null)
        println("missing-error")
    } catch (_: IllegalArgumentException) {
        println("variance-without-type")
    }

    try {
        KTypeProjection(null, typeOf<String>())
        println("missing-error")
    } catch (_: IllegalArgumentException) {
        println("type-without-variance")
    }
}
