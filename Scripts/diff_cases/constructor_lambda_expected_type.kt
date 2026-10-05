open class IntBase(val transform: (Int) -> Int)
object Derived : IntBase({ it + 1 })
class Capturing(offset: Int) : IntBase({ it + offset })

open class GenericBase<T>(val label: String = "base", val transform: (T) -> T)
object GenericDerived : GenericBase<String>(transform = { it + "!" })
class Secondary : GenericBase<Int> {
    constructor(offset: Int) : super(transform = { it + offset })
}
class Delegating<T>(val transform: (T) -> T) {
    constructor(marker: Int) : this(transform = { it })
}

open class NullableBase<T>(val transform: (T) -> Int)
object NullableDerived : NullableBase<String?>({ if (it == null) 0 else it.length })

open class Overloaded {
    val transform: (Int) -> Int
    constructor(transform: (Int) -> Int, marker: Int) { this.transform = transform }
    constructor(transform: (String) -> String, marker: String) { this.transform = { marker.length } }
}
object OverloadDerived : Overloaded({ it + 2 }, 7)

open class PairBase(val first: (Int) -> Int, val second: (String) -> String)
object PairDerived : PairBase(second = { it + "?" }, first = { it * 2 })

class Entry(val value: Int)
open class Holder(val transform: (Entry) -> Entry?)
object Reject : Holder({ null })

fun increment(value: Int): Int = value + 1
fun increment(value: String): String = value + "!"
object ReferenceDerived : IntBase(::increment)
class Container { object Named : IntBase({ it + 11 }) }
enum class Mode { FIRST, SECOND }

fun main() {
    println(Derived.transform(1))
    println(Capturing(3).transform(4))
    println(GenericDerived.label)
    println(GenericDerived.transform("generic"))
    println(Secondary(5).transform(6))
    println(Delegating<String>(0).transform("identity"))
    println(NullableDerived.transform(null))
    println(NullableDerived.transform("abc"))
    println(OverloadDerived.transform(8))
    println(PairDerived.first(9))
    println(PairDerived.second("pair"))
    println(ReferenceDerived.transform(10))
    val offset = 11
    val anonymous = object : GenericBase<Int>(transform = { it + offset }) {}
    println(anonymous.label)
    println(anonymous.transform(12))
    class Local : IntBase({ it + offset })
    println(Local().transform(13))
    println(Container.Named.transform(14))
    println(Mode.SECOND.ordinal)
    val entry = Entry(7)
    println(Reject.transform(entry) == null)
    println(entry.value)
}
