val typedDefaultWords: Array<String> = arrayOf("alpha", "beta")
val typedDefaultDoubles: DoubleArray = doubleArrayOf(1.5, 2.5)

class TypedReferenceDefault(vararg val values: String = typedDefaultWords)
fun topReferenceDefault(vararg values: String = typedDefaultWords): String =
    "${values.size}:" + if (values.isEmpty()) "-" else values[0]
class TypedMemberDefault {
    fun count(prefix: Int = 10, vararg values: String = typedDefaultWords): Int = prefix + values.size
}
fun typedDoubleDefault(vararg values: Double = typedDefaultDoubles): String =
    "${values.size}:" + if (values.isEmpty()) "-" else values[0].toString()
fun nullableReferenceDefault(vararg values: String? = arrayOf<String?>(null, "n")): Int = values.size

fun main() {
    val ctor = TypedReferenceDefault::class.constructors.single()
    val constructorParameter = ctor.parameters[0]
    println("ctor-flags:" + constructorParameter.isOptional + ":" + constructorParameter.isVararg)
    val omitted = ctor.callBy(emptyMap()) as TypedReferenceDefault
    println("ctor-default:" + omitted.values.size + ":" + omitted.values[0])
    println("ctor-empty:" + (ctor.callBy(mapOf(constructorParameter to emptyArray<String>())) as TypedReferenceDefault).values.size)
    val top = ::topReferenceDefault
    println("top-flags:" + top.parameters[0].isOptional + ":" + top.parameters[0].isVararg)
    println("top-default:" + top.callBy(emptyMap()))
    println("top-empty:" + top.callBy(mapOf(top.parameters[0] to emptyArray<String>())))
    println("top-values:" + top.callBy(mapOf(top.parameters[0] to arrayOf("given"))))
    val member = TypedMemberDefault()
    val bound = member::count
    val unbound = TypedMemberDefault::count
    println("bound-default:" + bound.callBy(emptyMap()))
    println("unbound-default:" + unbound.callBy(mapOf(unbound.parameters[0] to member)))
    println("member-prefix:" + bound.callBy(mapOf(bound.parameters[0] to 20)))
    println("member-empty:" + bound.callBy(mapOf(bound.parameters[1] to emptyArray<String>())))
    println("double-default:" + ::typedDoubleDefault.callBy(emptyMap()))
    println("double-empty:" + ::typedDoubleDefault.callBy(mapOf(::typedDoubleDefault.parameters[0] to doubleArrayOf())))
    println("nullable-elements:" + ::nullableReferenceDefault.callBy(emptyMap()))
    println("ordinary-function-default:" + topReferenceDefault())
    println("ordinary-constructor-default:" + TypedReferenceDefault().values.size)
}
