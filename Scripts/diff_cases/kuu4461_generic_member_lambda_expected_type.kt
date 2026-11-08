// KUU-4461: generic member function + lambda returning a subtype that
// mentions the enclosing class type parameter; the expected type's
// `RowType?` must stay caller-rigid instead of binding the candidate's
// class-parameter variable to the non-null receiver argument.
interface Cur { fun next(): QR<Boolean> }
interface QR<T> { val value: T }
class VQR<T>(override val value: T) : QR<T>
class CurImpl : Cur { override fun next(): QR<Boolean> = VQR(true) }

class Q<RowType : Any>(private val row: RowType) {
    fun <R> execute(mapper: (Cur) -> QR<R>): QR<R> = mapper(CurImpl())

    fun a(): QR<RowType?> = execute { VQR<RowType?>(row) }
    fun b(): RowType? = execute { VQR<RowType?>(row) }.value
    fun c(): RowType? = execute<RowType?> { VQR<RowType?>(row) }.value
    fun mapper2(c: Cur): RowType = row
    fun d(): RowType? = execute { c ->
        if (c.next().value) VQR(null) else VQR(mapper2(c))
    }.value
}

fun main() {
    val q = Q("hello")
    println(q.a().value)
    println(q.b())
    println(q.c())
    println(q.d())
}
