import kotlin.reflect.KFunction
import kotlin.reflect.typeOf

inline fun <reified T> typeName(value: T): String = T::class.simpleName ?: "unknown"
inline fun <reified T> T.receiverName(): String = typeName(this)
inline fun <reified T> T.receiverNullable(): Boolean = typeOf<T>().isMarkedNullable
inline fun <reified T> nullableType(value: T): Boolean = typeOf<T>().isMarkedNullable
inline fun <reified T> nameReference(): (T) -> String = ::typeName
inline fun <reified T> lazyNameReference(): () -> ((T) -> String) = { ::typeName }
interface RefMaker<T> { fun reference(): (T) -> String }
inline fun <reified T> objectMaker(): RefMaker<T> = object : RefMaker<T> {
    override fun reference(): (T) -> String = ::typeName
}
inline fun <reified A, reified B> pairName(first: A, second: B): String = typeName(first) + ":" + typeName(second)
inline fun <reified T> nullableReference(): (T?) -> Boolean = ::nullableType
inline fun <reified T> throwingName(value: T): String { throw IllegalStateException(typeName(value)) }
class Holder<T>(val value: T) {
    inline fun <reified U> label(other: U): String = typeName(other) + ":" + value.toString()
}
inline fun <reified T> mapLabels(holder: Holder<Int>, values: List<T>): List<String> = values.map(holder::label)
fun interface GenericName<T> { fun get(value: T): String }
inline fun <reified T> boundSam(holder: Holder<Int>): GenericName<T> = GenericName<T>(holder::label)
inline fun <reified T> nestedObjectMaker(): () -> RefMaker<T> = {
    object : RefMaker<T> { override fun reference(): (T) -> String = ::typeName }
}
fun interface Name { fun get(value: String): String }
fun printSam(name: Name) { println(name.get("sam")) }
fun exceptionName(error: Throwable): String {
    var cause = error
    while (cause.cause != null) cause = cause.cause!!
    return cause::class.simpleName ?: "unknown"
}
fun main() {
    val stringName: (String) -> String = ::typeName
    val intName: (Int) -> String = ::typeName
    val nullableName: (String?) -> String = ::typeName
    println(stringName("a"))
    println(intName.invoke(1))
    println(nullableName(null))
    val nullableFlag: (String?) -> Boolean = ::nullableType
    val nonNullableFlag: (String) -> Boolean = ::nullableType
    println(nullableFlag(null))
    println(nonNullableFlag("a"))
    val escapedString = nameReference<String>()
    val escapedInt = nameReference<Int>()
    println(escapedString("b"))
    println(escapedInt(2))
    println(escapedString("c"))
    val delayedString = lazyNameReference<String>()
    val delayedInt = lazyNameReference<Int>()
    println(delayedString()("delayed"))
    println(delayedInt()(4))
    println(objectMaker<String>().reference()("object"))
    val holder = Holder(3)
    val bound: (String) -> String = holder::label
    println(bound("bound"))
    println(listOf("x", "y").map(::typeName))
    printSam(::typeName)
    val pair: (String, Int) -> String = ::pairName
    println(pair("first", 5))
    println(nullableReference<String>()(null))
    val throwing: (String) -> String = ::throwingName
    try { throwing("throw") } catch (error: IllegalStateException) { println(error.message) }
    println(mapLabels(holder, listOf("first", "second")))
    println(boundSam<String>(holder).get("generic-sam"))
    println(nestedObjectMaker<String>()().reference()("nested-object"))
    val receiverOnly = "receiver"::receiverName
    println(receiverOnly())
    val receiverFunction: String.() -> String = String::receiverName
    println("function".receiverFunction())
    val nullableReceiver: String? = null
    val nullableReceiverOnly = nullableReceiver::receiverNullable
    val nullableReceiverContextual: () -> Boolean = nullableReceiver::receiverNullable
    println(nullableReceiverOnly())
    println(nullableReceiverContextual())
    val unboundNullableReceiver: (String?) -> Boolean = String?::receiverNullable
    println(unboundNullableReceiver(null))
    val reflected = stringName as KFunction<*>
    println(reflected.name)
    println(reflected.isInline)
    println(reflected.parameters.size)
    try { reflected.call("reflect") } catch (error: Throwable) { println(exceptionName(error)) }
}
