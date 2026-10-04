// BUG-155: a non-null value stored through a generic T? field must survive
// the following load, cast, and member call.

abstract class NullableSlot<T> {
    private var value: T? = null

    fun store(next: T) {
        value = next
    }

    @Suppress("UNCHECKED_CAST")
    fun load(): T {
        val result = value as T
        value = null
        return result
    }
}

class IntSlot : NullableSlot<Int>()
class LongSlot : NullableSlot<Long>()
class StringSlot : NullableSlot<String>()
class BooleanSlot : NullableSlot<Boolean>()
class NullableStringSlot : NullableSlot<String?>()

class Label(val text: String)
class LabelSlot : NullableSlot<Label>()

fun main() {
    val ints = IntSlot()
    ints.store(42)
    println(ints.load())
    ints.store(7)
    println(ints.load())

    val longs = LongSlot()
    longs.store(9000000000L)
    println(longs.load())

    val strings = StringSlot()
    strings.store("source")
    println(strings.load().length)

    val booleans = BooleanSlot()
    booleans.store(true)
    println(booleans.load())

    val nullable = NullableStringSlot()
    nullable.store(null)
    println(nullable.load() == null)
    nullable.store("nullable-value")
    println(nullable.load()?.length)

    val labels = LabelSlot()
    labels.store(Label("member"))
    println(labels.load().text)
}
