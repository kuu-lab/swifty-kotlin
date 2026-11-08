// KUU-4468: a bound callable reference to a member whose signature mentions
// the owner's type parameters must keep those parameters when the receiver is
// the generic self type. Previously the receiver constraint degenerated to
// `T <: T`, the solver substituted errorType, and `Ser(::onEvent)` inferred
// `Ser<Ev<<error>>>` so the `ser.onNext(Ev.Sub(observer, d))` call was
// rejected with KSWIFTK-SEMA-0002.

interface Observer<in T>

class Ser<E>(val cb: (E) -> Unit) {
    fun onNext(e: E) = cb(e)
}

class Outer<T> {
    private val ser = Ser(::onEvent)
    var lastD = -1
        private set

    fun subscribe(observer: Observer<T>, d: Int) {
        ser.onNext(Ev.Sub(observer, d))
    }

    private fun onEvent(e: Ev<T>) {
        if (e is Ev.Sub<*>) {
            lastD = e.d
        }
    }

    private sealed class Ev<out T> {
        class Sub<T>(val observer: Observer<T>, val d: Int) : Ev<T>()
    }
}

fun main() {
    val observer = object : Observer<String> {}
    val outer = Outer<String>()
    outer.subscribe(observer, 40)
    outer.subscribe(observer, 2)
    println(outer.lastD)
}
