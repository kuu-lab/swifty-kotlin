import kotlin.coroutines.*

// KUU-3801: `(Continuation<Unit>) -> Any?` is the erased runtime shape of
// `suspend () -> Unit`, so the unsafe `as` cast succeeds on the JVM.
fun foo(block: (Continuation<Unit>) -> Any?) {
    println("as-susp0: ${(block as? (suspend () -> Unit)) != null}")
    block as (suspend () -> Unit)
    println("cast-ok")
}

fun main() {
    foo {}
    val fn0: Any = {}
    try {
        fn0 as (suspend () -> Unit)
        println("fn0-as-susp0: no throw")
    } catch (e: ClassCastException) {
        println("fn0-as-susp0: CCE")
    }
    val fn1: Any = { x: Int -> }
    try {
        fn1 as (suspend () -> Unit)
        println("fn1-as-susp0: no throw")
    } catch (e: ClassCastException) {
        println("fn1-as-susp0: CCE")
    }
    val susp: suspend (Int) -> Unit = { }
    val suspAsAny: Any = susp
    println("susp-is-f2: ${suspAsAny is Function2<*, *, *>}")
    println("susp-is-suspfn1: ${suspAsAny is SuspendFunction1<*, *>}")
    val cont: Any = { c: Continuation<Unit> -> null }
    println("cont-is-suspfn0: ${cont is SuspendFunction0<*>}")
    println("cont-is-f1: ${cont is Function1<*, *>}")
}
