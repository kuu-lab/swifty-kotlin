// KUU-3025: a bodiless generic class followed by a declaration starting with
// a hard keyword (`fun`, `val`, `class`, …) lost its type-parameter list
// because the `>`-follower check in the type-argument lookahead rejected
// non-label-name tokens. The synthesized constructor then had zero type
// parameters and `Box()`/`Box<Int>()` failed overload resolution with
// KSWIFTK-SEMA-0002.

class Box<T>
class Crate<A, B>

interface Token<K>
interface Store<K, V>

class Box2<T>
val inferredBox: Box<Int> = Box()
val explicitBox = Box2<String>()
val nestedCrate: Crate<Int, String> = Crate()

fun <T> maybeNull(): T? = null

class Box3<T>
fun <T> wrap(value: T): Box3<T> = Box3()

object Host {
    class Delegate<D, E, R>
    fun <D, E, R> delegate(): Delegate<D, E, R> = Delegate()
}

class After<T>
fun checksOut(): Boolean {
    val wrapped = wrap(7)
    val delegated = Host.delegate<Host, Int, String>()
    return true
}

fun main() {
    println(if (checksOut()) "OK" else "FAIL")
}
