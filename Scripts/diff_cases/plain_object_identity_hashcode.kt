// KUU-1074: inherited hashCode must depend on identity, not class or fields.
class Plain
class MutablePlain(var value: Int)
data class Value(val value: Int)
class Custom {
    override fun hashCode(): Int = 1074
}

fun main() {
    // Keep both instances alive and compare properties, not JVM-specific hashes.
    val firstAny = Any()
    val secondAny = Any()
    println(firstAny.hashCode() != secondAny.hashCode())
    println(firstAny.hashCode() == firstAny.hashCode())

    val first = Plain()
    val second = Plain()
    println(first.hashCode() != second.hashCode())
    val erasedFirst: Any = first
    val erasedSecond: Any = second
    println(erasedFirst.hashCode() == first.hashCode())
    println(erasedFirst.hashCode() != erasedSecond.hashCode())

    val mutable = MutablePlain(1)
    val hash = mutable.hashCode()
    val erasedMutable: Any = mutable
    val list = listOf(erasedMutable)
    val listHash = list.hashCode()
    val keys = hashSetOf(erasedMutable)
    mutable.value = 2
    println(mutable.hashCode() == hash)
    println(erasedMutable.hashCode() == hash)
    println(list.hashCode() == listHash)
    println(keys.contains(mutable))

    val value = Value(42)
    val erasedValue: Any = value
    println(value.hashCode())
    println(erasedValue.hashCode())
    println(Value(42).hashCode() == value.hashCode())

    val custom = Custom()
    val erasedCustom: Any = custom
    println(custom.hashCode())
    println(erasedCustom.hashCode())
}
