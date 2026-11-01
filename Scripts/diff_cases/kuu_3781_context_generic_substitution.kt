// Regression (KUU-3781): a generic function whose context parameters
// mention its own type parameters must substitute the call-site type
// arguments when resolving the implicit receivers. Mirrors the JetBrains
// contextParameters/substitutedContextReceivers.kt case that SIGSEGV'd on
// the ticket's baseline.

class Box<E>(val x: E)

context(box: Box<X>, y: Y)
fun <X, Y : Number> bar(): String = box.x.toString() + y.toString()

fun main() {
    println(with(Box("OK")) {
        with(56) {
            bar<String, Int>()
        }
    })
}
