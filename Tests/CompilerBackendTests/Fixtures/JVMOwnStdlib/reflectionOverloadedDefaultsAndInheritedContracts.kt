import kotlin.reflect.KParameter
import kotlin.reflect.KFunction
import kotlin.reflect.KProperty1
import kotlin.reflect.full.memberFunctions
import kotlin.reflect.full.memberProperties

fun pick(value: Int = 7): String = "i:$value"
fun pick(value: String = "s"): String = "s:$value"
fun String.suffix(value: Int = 9): String = "$this:$value"
fun primitiveBy(value: Int): Int = value + 1
fun unitBy(value: String = "unit-by") { println(value) }
class DefaultMethods {
    fun pick(value: Int = 8): String = "mi:$value"
    fun pick(value: String = "m"): String = "ms:$value"
}
class DefaultBox(val text: String, val marker: Boolean) {
    constructor(value: Int = 7): this("bi:$value", true)
    constructor(value: String = "s"): this("bs:$value", true)
}
open class Parent {
    open fun overridden(): CharSequence = "parent"
    fun inherited(value: Int): Int = value + 1
    open val text: CharSequence get() = "parent-property"
    val inheritedProperty: Int get() = 42
    private fun hidden(): Int = 0
}
interface Named { fun named(): String }
interface GenericValue<T> { fun generic(value: T): T }
class Child: Parent(), Named, GenericValue<String> {
    override fun overridden(): String = "child"
    override val text: String get() = "child-property"
    override fun named(): String = "named"
    override fun generic(value: String): String = value
}
class ParameterA { fun value(value: Int): Int = value }
class ParameterB { fun value(value: Int): Int = value }

fun namedFunction(functions: Collection<KFunction<*>>, name: String): KFunction<*> {
    var found: KFunction<*>? = null
    var count = 0
    for (function in functions) if (function.name == name) { found = function; count++ }
    if (count != 1) throw IllegalStateException("Expected one function: $name")
    return found!!
}
fun namedProperty(properties: Collection<KProperty1<Child, *>>, name: String): KProperty1<Child, *> {
    var found: KProperty1<Child, *>? = null
    var count = 0
    for (property in properties) if (property.name == name) { found = property; count++ }
    if (count != 1) throw IllegalStateException("Expected one property: $name")
    return found!!
}
fun memberCount(name: String): Int {
    var count = 0
    for (member in Child::class.members) if (member.name == name) count++
    return count
}

fun main() {
    val intPick: (Int) -> String = ::pick
    val stringPick: (String) -> String = ::pick
    println((intPick as KFunction<*>).callBy(emptyMap<KParameter, Any?>()))
    println((stringPick as KFunction<*>).callBy(emptyMap<KParameter, Any?>()))
    val methods = DefaultMethods()
    val memberInt: (DefaultMethods, Int) -> String = DefaultMethods::pick
    val memberString: (String) -> String = methods::pick
    val member = memberInt as KFunction<*>
    println(member.callBy(mapOf(member.parameters[0] to methods)))
    println((memberString as KFunction<*>).callBy(emptyMap<KParameter, Any?>()))
    val suffix = "extension"::suffix
    println(suffix.callBy(emptyMap()))
    val intBox: (Int) -> DefaultBox = ::DefaultBox
    val stringBox: (String) -> DefaultBox = ::DefaultBox
    println(((intBox as KFunction<*>).callBy(emptyMap<KParameter, Any?>()) as DefaultBox).text)
    println(((stringBox as KFunction<*>).callBy(emptyMap<KParameter, Any?>()) as DefaultBox).text)
    println((intBox as KFunction<*>).returnType.classifier == DefaultBox::class)
    println((stringBox as KFunction<*>).returnType.isMarkedNullable)

    val child = Child()
    val functions = Child::class.memberFunctions
    println(namedFunction(functions, "inherited").call(child, 41))
    println(namedFunction(functions, "overridden").call(child))
    println(namedFunction(functions, "named").call(child))
    println(namedFunction(functions, "generic").call(child, "generic"))
    println(memberCount("hidden") != 0)
    val properties = Child::class.memberProperties
    println(namedProperty(properties, "inheritedProperty").get(child))
    println(namedProperty(properties, "text").get(child))
    println(memberCount("overridden"))
    println(memberCount("text"))
    println(memberCount("generic"))

    val a = ParameterA::value
    val b = ParameterB::value
    println(a.parameters[1] == b.parameters[1])
    println(a.parameters[1] == (ParameterA::value).parameters[1])
    try {
        a.callBy(mapOf(a.parameters[0] to ParameterA(), b.parameters[1] to 10))
    } catch (failure: IllegalArgumentException) { println("wrong parameter rejected") }
    println(a.callBy(mapOf(a.parameters[0] to ParameterA(), a.parameters[1] to 11)))
    val primitive = ::primitiveBy
    println(primitive.callBy(mapOf(primitive.parameters[0] to 11)))
    val unit = ::unitBy
    println(unit.callBy(emptyMap<KParameter, Any?>()) == Unit)
}
