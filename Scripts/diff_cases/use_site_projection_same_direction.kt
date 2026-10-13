// KUU-1381: a use-site `in` projection on an `in`-declared parameter is
// redundant and keeps the contravariant direction (kotlinc: warning only).
interface Sink<in T> { fun put(t: T) }
class IS<T> : Sink<T> {
    override fun put(t: T) { println("put") }
}

interface Box<out T> { fun get(): T }
class IB<T>(val v: T) : Box<T> { override fun get() = v }

class IC<T>(val v: T)

fun main() {
    // in-projection on in-decl: admits Sink<S> whenever the written arg <: S
    val s: Sink<in Int> = IS<Number>()
    s.put(9)
    val s2: Sink<in Number> = IS<Number>()
    s2.put(3)
    val s3: Sink<in Int> = IS<Int>()
    s3.put(7)

    // star and out-direction neighbours keep working
    val f: Sink<*> = IS<Number>()
    val b: Box<out Int> = IB<Int>(4)
    println(b.get())

    // in/out projections on an invariant class are plain arguments
    val i: IC<in Int> = IC<Int>(3)
    val j: IC<out Number> = IC<Int>(5)
    println(i.v)
    println(j.v)
    println("done")
}
