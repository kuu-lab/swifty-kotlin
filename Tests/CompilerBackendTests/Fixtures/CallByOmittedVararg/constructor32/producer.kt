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
