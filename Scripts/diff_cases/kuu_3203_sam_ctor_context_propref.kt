// KUU-3203: upstream codegen/box shape
// callableReference/adaptedReferences/contextTypeWithSam — the SAM
// constructor argument `::foo.get()` is a call on a property reference that
// produces a context-receiver function value.
class C(var a: String) {
    fun foo(): String { return a }
}

context(ctx: T)
fun <T> implicit(): T = ctx

fun interface SamInterface {
    context(i: C)
    fun accept(): String
}

val foo: context(C) () -> String
    get() = { implicit<C>().foo() }

val samObject = SamInterface(::foo.get())

fun main() {
    with(C("OK")) {
        println(samObject.accept())
    }
}
