// Regression: a member `context(...) val p` read on a generic owner bound
// only the property identifier, so the getter call lost its context receiver
// binding and owner type arguments (KUU-3170, substitutedContextReceivers).
class Box<E>(val x: E)

class A<X, Y : Number> {
    context(box: Box<X>, y: Y)
    val p1: String get() = box.x.toString() + y.toString()
}

fun main() {
    with(Box("O")) {
        with(33) {
            println(A<String, Int>().p1)
        }
    }
}
