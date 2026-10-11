val packedDefaultWords: Array<String> = arrayOf("default", "second")

class PackedInts(vararg val values: Int)
class PackedStrings(vararg val values: String)
class PackedDoubles(vararg val values: Double)
class PackedOptional(vararg val values: String = packedDefaultWords)
class PackedRequired(val prefix: String, vararg val values: Double)
class PackedPlain(val value: Int)

fun packedTop(vararg values: String): Int = values.size
fun packedTopDefault(vararg values: String = packedDefaultWords): Int = values.size
fun packedRequiredTop(prefix: Int, vararg values: Double): Int = prefix + values.size
class PackedMember {
    fun count(prefix: Int = 40, vararg values: String = packedDefaultWords): Int = prefix + values.size
}
fun packedFailure(block: () -> Any?): String = try {
    block()
    "OK"
} catch (error: IllegalArgumentException) {
    "IAE"
}

fun main() {
    val ints = ::PackedInts
    val strings = ::PackedStrings
    val doubles = ::PackedDoubles
    println("ctor-int:" + ints.callBy(emptyMap()).values.size)
    println("ctor-string:" + strings.callBy(emptyMap()).values.size)
    println("ctor-double:" + doubles.callBy(emptyMap()).values.size)
    println("ctor-int-empty:" + ints.callBy(mapOf(ints.parameters[0] to intArrayOf())).values.size)
    println("ctor-string-empty:" + strings.callBy(mapOf(strings.parameters[0] to emptyArray<String>())).values.size)
    println("ctor-double-empty:" + doubles.callBy(mapOf(doubles.parameters[0] to doubleArrayOf())).values.size)
    val integerValues = intArrayOf(1, 2)
    val stringValues = arrayOf("a", "b")
    val doubleValues = doubleArrayOf(1.5, 2.5)
    val givenInts = ints.callBy(mapOf(ints.parameters[0] to integerValues))
    val givenStrings = strings.callBy(mapOf(strings.parameters[0] to stringValues))
    val givenDoubles = doubles.callBy(mapOf(doubles.parameters[0] to doubleValues))
    println("ctor-values:" + givenInts.values.size + ":" + givenStrings.values.size + ":" + givenDoubles.values.size)
    println("primitive-identity:" + (givenInts.values === integerValues) + ":" + (givenDoubles.values === doubleValues))
    println("reference-identity:" + (givenStrings.values === stringValues))
    integerValues[0] = 9
    stringValues[0] = "changed"
    println("caller-mutation:" + givenInts.values[0] + ":" + givenStrings.values[0])
    println("primitive-wrong-array:" + packedFailure { ints.callBy(mapOf(ints.parameters[0] to emptyArray<Int>())) })
    println("reference-wrong-component:" + packedFailure { strings.callBy(mapOf(strings.parameters[0] to emptyArray<Int>())) })
    val optional = ::PackedOptional
    val defaulted = optional.callBy(emptyMap())
    println("ctor-default:" + defaulted.values.size + ":" + defaulted.values[0])
    println("ctor-default-identity:" + (defaulted.values === packedDefaultWords))
    println("ctor-optional-empty:" + optional.callBy(mapOf(optional.parameters[0] to emptyArray<String>())).values.size)
    println("ctor-flags:" + ints.parameters[0].isOptional + ":" + ints.parameters[0].isVararg + ":" + optional.parameters[0].isOptional + ":" + optional.parameters[0].isVararg)
    val required = ::PackedRequired
    println("ctor-required-missing:" + packedFailure { required.callBy(emptyMap()) })
    val requiredGiven = required.callBy(mapOf(required.parameters[0] to "p"))
    println("ctor-required-given:" + requiredGiven.prefix + ":" + requiredGiven.values.size)
    println("top-omitted:" + ::packedTop.callBy(emptyMap()))
    println("top-default:" + ::packedTopDefault.callBy(emptyMap()))
    val top = ::packedTopDefault
    println("top-default-empty:" + top.callBy(mapOf(top.parameters[0] to emptyArray<String>())))
    val requiredTop = ::packedRequiredTop
    println("top-required-missing:" + packedFailure { requiredTop.callBy(emptyMap()) })
    println("top-required-given:" + requiredTop.callBy(mapOf(requiredTop.parameters[0] to 10)))
    val member = PackedMember()
    val bound = member::count
    val unbound = PackedMember::count
    println("bound-default:" + bound.callBy(emptyMap()))
    println("unbound-default:" + unbound.callBy(mapOf(unbound.parameters[0] to member)))
    println("member-receiver-missing:" + packedFailure { unbound.callBy(emptyMap()) })
    println("bound-explicit-empty:" + bound.callBy(mapOf(bound.parameters[1] to emptyArray<String>())))
    val normal = ::PackedPlain
    println("normal-constructor-reference:" + normal(7).value)
    println("normal-direct-vararg:" + PackedInts(3, 4).values.size + ":" + PackedStrings("x", "y").values.size)
    println("normal-direct-default:" + PackedOptional().values.size + ":" + packedTopDefault())
    println("class-constructor-control:" + PackedInts::class.constructors.single().callBy(emptyMap()).values.size)
    println("normal-component-control:" + stringValues.size)
}
