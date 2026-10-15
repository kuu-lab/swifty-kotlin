// KUU-2373: delegated interface member extensions keep dispatch and extension receivers.
fun interface Base {
    fun String.print(): String
}
val String.foo: String
    get() = this
class Derived(b: Base) : Base by b
fun box(): String {
    val a = Derived(Base(String::foo))
    with(a) {
        return "OK".print()
    }
}

fun interface Minimal { fun String.print(): String }
class MinimalImpl : Minimal { override fun String.print() = this }
class MinimalDirect : Minimal { override fun String.print() = "direct:${this}" }
class MinimalDelegate(delegate: Minimal) : Minimal by delegate

interface TypedParent<T> { fun T.decorate(): String }
interface MultiPrinter<T> : TypedParent<T> {
    fun Any.describe(): String
    fun String.describe(): String
    fun Int.describe(): String
}
class MultiPrinterImpl : MultiPrinter<String> {
    override fun Any.describe() = "Any:${this}"
    override fun String.describe() = "String:${this}"
    override fun Int.describe() = "Int:${this}"
    override fun String.decorate() = "Inherited:${this}"
}
class GenericPrinterDelegate<T>(delegate: MultiPrinter<T>) : MultiPrinter<T> by delegate

interface Plain { fun text(): String }
class PlainImpl : Plain { override fun text() = "plain" }
class PlainDelegate(delegate: Plain) : Plain by delegate

fun main() {
    println(box())
    println(with(MinimalDelegate(MinimalImpl())) { "OK".print() })
    println(with(MinimalImpl()) { "base".print() })
    println(with(MinimalDirect()) { "OK".print() })
    println(with(GenericPrinterDelegate(MultiPrinterImpl())) { "OK".describe() })
    println(with(GenericPrinterDelegate(MultiPrinterImpl())) { 42.describe() })
    println(with(GenericPrinterDelegate(MultiPrinterImpl())) { "OK".decorate() })
    println(PlainDelegate(PlainImpl()).text())
}
