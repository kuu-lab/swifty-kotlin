// Regression based on JetBrains/Kotlin KT-69215 at commit 679366a83f99851b42f64795f10ed803ff011c73.
interface Callback {
    fun foo()
}

interface SuccessCallback<in T1> {
    fun onSuccess(value: T1)
}

interface MaybeCallbacks<in T2> : SuccessCallback<T2>, Callback

interface Disposable
interface Observer<in T3> {
    fun onSubscribe(disposable: Disposable)
}

interface MaybeObserver<in T4> : Observer<T4>, MaybeCallbacks<T4>

fun <T4> test(emitter: MaybeCallbacks<T4>) {
    class OuterLocal<T5> : MaybeObserver<T4>, Callback by emitter {
        override fun onSubscribe(disposable: Disposable) {}

        override fun onSuccess(value: T4) {
            class InnerLocal : MaybeObserver<T4>, Observer<T4> by this, MaybeCallbacks<T4> by emitter {}
        }
    }
}

interface P { fun f(): String }
object Delegate : P { override fun f() = "OK" }

fun call(): String {
    class Local : P by Delegate
    return Local().f()
}

fun capturedCall(): String {
    val delegate = Delegate
    class CapturedLocal : P by delegate
    return CapturedLocal().f()
}

fun box() = if (capturedCall() == "OK") call() else "FAIL"
fun main() { println(box()) }
