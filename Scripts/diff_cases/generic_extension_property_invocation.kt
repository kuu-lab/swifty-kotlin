class Box<T>(var value: T)
class Action<T> { operator fun invoke(value: T): T = value }
var reads = 0
val <T> Box<T>.read: () -> T get() { reads++; return { value } }
val <T> Box<T>.callback: Action<T> get() = Action<T>()
val <T> Box<T>.apply: (Box<T>.() -> Unit) -> Int get() = { block -> block(this); 42 }
val <T> T.echo: () -> T get() = { this }
val <T : Any> Box<T>.bounded: T get() = value
val <T> Box<T>.whereRead: () -> T where T : Any get() = { value }
var <T> Box<T>.entry: T get() = value; set(v) { value = v }
val <T> Box<T>.item get() = value
val <T> Box<T>.transform: (T) -> T get() = { it }
class Provider<S>(val prefix: S) {
    val <T> Box<T>.prefixed: () -> S get() = { prefix }
    fun use(box: Box<Int>): S = box.prefixed()
}
class BoundedProvider<S> {
    val <T : S> Box<T>.boundRead: () -> T get() = { value }
}
fun <U> identity(value: U): U = value
inline val <reified T> T.kind: (Any) -> Boolean get() = { it is T }
inline fun <reified U> makeKind(value: U): () -> Boolean = { value.kind(1) }
inline val <reified T> T.nullableKind: (Any?) -> Boolean get() = { it is T }
inline fun <reified U> makeNullableKind(value: U?): (Any?) -> Boolean = value.nullableKind
inline fun <reified U> makeNestedNullableKind(value: U?): (Any?) -> Boolean = { value.nullableKind(it) }
class DeferredAction<S>(val result: S) { operator fun invoke(): S = result }
class DelayedProvider<S>(val result: S) {
    val <T> Box<T>.action: DeferredAction<S> get() = DeferredAction(result)
    fun later(box: Box<Int>): () -> S = { box.action() }
}
class Shadow<T> {
    val <T> Box<T>.shadowed: () -> T get() = { identity<T>(value) }
    fun use(box: Box<String>): String = box.shadowed()
}
fun main() {
    val text = Box("typed")
    println(text.read())
    val integers = Box(8)
    println(integers.read())
    println(integers.callback(2))
    println(text.callback("nominal"))
    val block: Box<Int>.() -> Unit = { println(value) }
    println(integers.apply(block))
    println("echo".echo())
    println(9.echo())
    println(text.bounded)
    println(text.whereRead())
    text.entry = "changed"
    println(text.entry)
    println(text.read())
    println(text.transform("identity"))
    println(Provider("prefix").use(integers))
    println(Shadow<Int>().use(text))
    val absent: Box<String>? = null
    val present: Box<String>? = text
    println(absent?.read())
    println("reads:$reads")
    println(present?.read())
    println("reads:$reads")
    val inferred: String = text.item
    println(inferred)
    with(Provider("direct")) { println(Box(1).prefixed()) }
    with(BoundedProvider<String>()) { println(Box("bound").boundRead()) }
    println(1.kind(1))
    println(1.kind("x"))
    println(makeKind(1)())
    println(makeKind("x")())
    val nullableKind = makeNullableKind<String>(null)
    println(nullableKind(null))
    println(nullableKind("x"))
    println(nullableKind(1))
    val nestedNullableKind = makeNestedNullableKind<String>(null)
    println(nestedNullableKind(null))
    println(nestedNullableKind("x"))
    println(nestedNullableKind(1))
    println(DelayedProvider("captured").later(Box(1))())
}
