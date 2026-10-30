// KUU-3173 regression adapted from Kotlin testData
// codegen/box/bridges/delegationComplex.kt. A generic forwarding method must
// return the value produced by the delegate when the delegate expression is
// an unchecked cast to a generic interface — not the null default result.
open class Content {
    override fun toString() = "OK"
}

interface Box<E> {
    fun get(): E
}

interface ContentBox<T : Content> : Box<T>

object Impl : ContentBox<Content> {
    override fun get(): Content = Content()
}

class ContentBoxDelegate<T : Content> : ContentBox<T> by (Impl as ContentBox<T>)

fun main() {
    println(ContentBoxDelegate<Content>().get().toString())
}
