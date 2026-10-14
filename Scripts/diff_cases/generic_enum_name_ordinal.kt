// KUU-2037: abstract Enum receivers must read tagged enum boxes, not stored fields.
fun <T : Enum<T>> enumName(value: T): String = value.name
fun <T : Enum<T>> enumOrdinal(value: T): Int = value.ordinal
fun <T : Enum<T>> names(values: Array<T>): String = values.joinToString { it.name }
fun <T : Enum<T>> ordinals(values: Array<T>): String = values.joinToString { it.ordinal.toString() }
fun <T : Enum<T>> T.implicitName(): String = name
fun <T : Enum<T>> T.implicitOrdinal(): Int = ordinal
fun <T : Enum<T>> T.same(other: T): Boolean = this == other
fun <T : Enum<T>> safeName(value: T?): String? = value?.name
fun <T : Enum<T>> safeOrdinal(value: T?): Int? = value?.ordinal
fun baseName(value: Enum<*>): String = value.name
fun baseOrdinal(value: Enum<*>): Int = value.ordinal
fun Enum<*>.baseImplicitName(): String = name
fun Enum<*>.baseImplicitOrdinal(): Int = ordinal
inline fun <T : Enum<T>> inlineName(value: T): String = value.name
inline fun inlineBaseName(value: Enum<*>): String = value.name
inline fun <T : Enum<T>> T.inlineImplicitName(): String = name
class Named(val name: String, val ordinal: Int)
enum class E { A, B }
enum class Other { A, C; override fun toString(): String = "override" }
fun main() {
    println(enumName(E.A))
    println(enumName(E.B))
    println(enumOrdinal(E.A))
    println(enumOrdinal(E.B))
    println(names(E.values()))
    println(ordinals(E.values()))
    println(E.B.implicitName())
    println(E.B.implicitOrdinal())
    println(safeName(E.B))
    println(safeName<E>(null))
    println(safeOrdinal(E.A))
    println(safeOrdinal<E>(null))
    println(baseName(Other.C))
    println(baseOrdinal(Other.C))
    println(enumName(Other.C))
    println(Other.C.toString())
    val boxed: Any = E.B
    println(enumName(boxed as E))
    println(E.B.name)
    println(E.B.ordinal)
    val named = Named("field", 7)
    println(named.name)
    println(named.ordinal)
    println(inlineName(E.A))
    println(inlineBaseName(E.B))
    println(E.B.inlineImplicitName())
    val otherBoxed: Any = Other.C
    println(otherBoxed)
    println(names(Other.values()))
    println(E.A.baseImplicitName())
    println(Other.C.baseImplicitOrdinal())
    println((boxed as E).same(E.B))
    println((otherBoxed as Other).same(Other.C))
    println(E.B.same(E.B))
}
