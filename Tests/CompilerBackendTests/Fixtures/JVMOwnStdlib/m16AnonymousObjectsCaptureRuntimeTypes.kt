interface Probe {
    val initial: Boolean
    val name: String
    fun matches(v: Any?): Boolean
    fun cast(v: Any?): Any?
    fun safe(v: Any?): Any?
    fun array(n: Int): Array<out Any?>
    fun nested(): (Any?) -> Boolean
}
inline fun <reified T> probe(seed: Any?): Probe = object: Probe {
    override val initial = seed is T
    override val name: String get() = T::class.java.name
    override fun matches(v: Any?): Boolean = v is T
    override fun cast(v: Any?): Any? = v as T
    override fun safe(v: Any?): Any? = v as? T
    override fun array(n: Int): Array<out Any?> = arrayOfNulls<T>(n)
    override fun nested(): (Any?) -> Boolean = { it is T }
}
interface Box<T> { fun get(): T; fun matches(v: Any?): Boolean }
inline fun <reified T> box(value: T): Box<T> = object: Box<T> {
    override fun get(): T = value
    override fun matches(v: Any?): Boolean = v is T
}
fun main() {
    val a = probe<Int>(1); val b = probe<String?>(null)
    println(a.javaClass == probe<Int>(2).javaClass)
    println(a.initial); println(b.initial); println(a.name); println(b.name)
    println(a.matches(2)); println(a.matches("wrong")); println(a.matches(null)); println(b.matches(null))
    println(a.cast(7)); println(a.safe("wrong")); println(b.cast(null))
    println(a.array(2).javaClass.name); println(b.array(1).javaClass.name)
    println(a.nested()(1)); println(b.nested()(null))
    try { a.cast(null) } catch (e: NullPointerException) { println("null") }
    try { a.cast("wrong") } catch (e: ClassCastException) { println("cast") }
    val x = box(9); val y = box("text"); println(x.get()); println(y.get()); println(x.matches("wrong")); println(y.matches("yes"))
}
