import kotlin.reflect.KCallable

class IntValues(vararg values: Int) { val count = values.size }
class StringValues(vararg values: String) { val count = values.size }
class DoubleValues(vararg values: Double) { val count = values.size }
class WithDefault(val label: String = "default", vararg values: Int) { val count = values.size }
class DefaultAfter(vararg values: String, val label: String = "tail") { val count = values.size }
class WithRequired(val label: String, vararg values: Int) { val count = values.size }
class OptionalInts(vararg val values: Int = intArrayOf(9))
annotation class Tags(vararg val values: String)

fun intCount(vararg values: Int) = values.size
fun stringCount(vararg values: String) = values.size
fun doubleCount(vararg values: Double) = values.size
fun mixedCount(label: String = "function", vararg values: Int): String = label + ":" + values.size
class Counter(val base: Int) {
    fun count(vararg values: Int, shift: Int = 2): Int = base + shift + values.size
}

fun failure(call: () -> Any?): String = try {
    call()
    "OK"
} catch (failure: IllegalArgumentException) {
    "IAE"
}

fun main() {
    val ints = IntValues::class.constructors.single()
    val strings = StringValues::class.constructors.single()
    val doubles = DoubleValues::class.constructors.single()
    println("constructor-int:" + (ints.callBy(emptyMap()) as IntValues).count)
    println("constructor-string:" + (strings.callBy(emptyMap()) as StringValues).count)
    println("constructor-double:" + (doubles.callBy(emptyMap()) as DoubleValues).count)
    println("explicit-int-empty:" + (ints.callBy(mapOf(ints.parameters[0] to intArrayOf())) as IntValues).count)
    println("explicit-string-empty:" + (strings.callBy(mapOf(strings.parameters[0] to emptyArray<String>())) as StringValues).count)
    println("explicit-double-empty:" + (doubles.callBy(mapOf(doubles.parameters[0] to doubleArrayOf())) as DoubleValues).count)
    println("provided-int:" + (ints.callBy(mapOf(ints.parameters[0] to intArrayOf(1, 2))) as IntValues).count)
    println("provided-string:" + (strings.callBy(mapOf(strings.parameters[0] to arrayOf("a", "b"))) as StringValues).count)
    println("provided-double:" + (doubles.callBy(mapOf(doubles.parameters[0] to doubleArrayOf(1.5, 2.5))) as DoubleValues).count)
    val before = WithDefault::class.constructors.single()
    val omittedBefore = before.callBy(emptyMap()) as WithDefault
    println("default-before:" + omittedBefore.label + ":" + omittedBefore.count)
    val givenBefore = before.callBy(mapOf(before.parameters[0] to "given")) as WithDefault
    println("given-before:" + givenBefore.label + ":" + givenBefore.count)
    val after = DefaultAfter::class.constructors.single()
    val omittedAfter = after.callBy(emptyMap()) as DefaultAfter
    println("default-after:" + omittedAfter.label + ":" + omittedAfter.count)
    val givenAfter = after.callBy(mapOf(after.parameters[1] to "given")) as DefaultAfter
    println("given-after:" + givenAfter.label + ":" + givenAfter.count)
    val required = WithRequired::class.constructors.single()
    println("missing-required:" + failure { required.callBy(emptyMap()) })
    val givenRequired = required.callBy(mapOf(required.parameters[0] to "required")) as WithRequired
    println("provided-required:" + givenRequired.label + ":" + givenRequired.count)
    println("wrong-array:" + failure { ints.callBy(mapOf(ints.parameters[0] to emptyArray<Int>())) })
    val optional = OptionalInts::class.constructors.single()
    val omittedOptional = optional.callBy(emptyMap()) as OptionalInts
    println("optional-vararg:" + omittedOptional.values.size + ":" + omittedOptional.values[0])
    println("optional-explicit-empty:" + (optional.callBy(mapOf(optional.parameters[0] to intArrayOf())) as OptionalInts).values.size)
    println("annotation-empty:" + (Tags::class.constructors.single().callBy(emptyMap()) as Tags).values.size)
    println("function-int:" + ::intCount.callBy(emptyMap()))
    println("function-string:" + ::stringCount.callBy(emptyMap()))
    println("function-double:" + ::doubleCount.callBy(emptyMap()))
    println("function-default:" + ::mixedCount.callBy(emptyMap()))
    val callable: KCallable<Int> = ::intCount
    println("interface-callable:" + callable.callBy(emptyMap()))
    val bound = Counter(10)::count
    println("bound-default:" + bound.callBy(emptyMap()))
    println("bound-shift:" + bound.callBy(mapOf(bound.parameters[1] to 5)))
    val unbound = Counter::count
    println("unbound-default:" + unbound.callBy(mapOf(unbound.parameters[0] to Counter(20))))
    println("missing-receiver:" + failure { unbound.callBy(emptyMap()) })
    val parameter = ints.parameters.single()
    println("parameter-flags:" + parameter.isOptional + ":" + parameter.isVararg + ":" + parameter.type)
}
