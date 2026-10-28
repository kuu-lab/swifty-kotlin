// KUU-3526: a receiver SAM lambda must read an extension property on its
// extension receiver (JetBrains extensionPropertyInSAMInterface.kt).
fun interface SamInterface {
    fun Int.accept(): String
}

val Int.a: String
    get() = "OK"

val b = SamInterface { a }

fun main() {
    with(b) {
        println(1.accept())
    }
}
