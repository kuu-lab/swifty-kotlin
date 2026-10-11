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
