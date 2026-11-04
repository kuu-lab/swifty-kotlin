class AtomicRef<T>(var v: T)

class Holder(val x: Int?)

// MVIKotlin `initAndGet`: the `T?` in the receiver shape owns its `?`, so
// `AtomicRef<Holder?>` must infer `T = Holder`, not `Holder?` (KUU-3976).
private inline fun <T : Any> AtomicRef<T?>.initAndGet(init: () -> T): T = init()

fun <T : Any> AtomicRef<T?>.each(block: (T) -> Unit): T? = v.also { it?.let(block) }

fun main() {
    val ref = AtomicRef<Holder?>(null)
    val r = ref.initAndGet { Holder(null) }
    println(r.x)
    val r2 = ref.initAndGet { Holder(7) }
    println(r2.x)
    AtomicRef<Int?>(2).each { println(it * 10) }
}
