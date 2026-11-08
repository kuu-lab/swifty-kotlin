// KUU-4464: a generic call used as a combinator lambda's result must pick
// up its type variable from the enclosing expected type — `?.let { resolve(..) }`
// against `T?` and `listOf<T>() + flatMap { getAll(..) }` against `List<T>`
// (koin-core InstanceRegistry/Scope shapes). kotlinc accepts both.
class TQ(val v: String)
class Ctx(val sa: TQ?)

class Reg {
    fun <T> resolve(q: TQ, c: Ctx): T? = null
    fun <T> f(c: Ctx): T? = c.sa?.let { resolve(it, c) }
}

class Sc {
    fun <T> getAll(c: String): List<T> = listOf()
    fun <T> all(l: List<String>): List<T> =
        listOf<T>() + l.flatMap { k -> getAll(k) }
}

fun main() {
    val reg = Reg()
    val ctx = Ctx(TQ("x"))
    val inferred: String? = reg.f(ctx)
    println(inferred)
    println(reg.f<String>(ctx))
    println(Sc().all<String>(listOf("a", "b")).size)
}
