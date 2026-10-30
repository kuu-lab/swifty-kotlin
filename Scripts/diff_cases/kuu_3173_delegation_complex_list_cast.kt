// KUU-3173 regression adapted from Kotlin testData
// codegen/box/bridges/delegationComplexWithList.kt. The delegated List<T>
// members must forward through the unchecked-cast delegate expression to the
// concrete impl instead of falling back to a null result.
open class Content {
    override fun toString() = "OK"
}

interface ContentBox<T : Content> : List<T>

object Impl : ContentBox<Content>, AbstractList<Content>() {
    override fun get(index: Int) = Content()

    override val size: Int
        get() = throw UnsupportedOperationException()
}

class ContentBoxDelegate<T : Content> : ContentBox<T> by (Impl as ContentBox<T>)

fun main() {
    println(ContentBoxDelegate<Content>()[0].toString())
}
