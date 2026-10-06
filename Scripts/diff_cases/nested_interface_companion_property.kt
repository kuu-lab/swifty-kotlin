package sample

// KUU-1308: nested interface qualifiers must resolve before companion lookup.
class Outer {
    fun value() = Inner.Slot.VALUE
    fun qualifiedValue() = Outer.Inner.Slot.VALUE
    fun fullyQualifiedValue() = sample.Outer.Inner.Slot.VALUE
    class Inner {
        interface Slot {
            companion object { val VALUE = 42 }
        }
    }
}

fun main() {
    println(Outer().value())
    println(Outer().qualifiedValue())
    println(Outer().fullyQualifiedValue())
    println(Outer.Inner.Slot.VALUE)
    println(sample.Outer.Inner.Slot.VALUE)
}
