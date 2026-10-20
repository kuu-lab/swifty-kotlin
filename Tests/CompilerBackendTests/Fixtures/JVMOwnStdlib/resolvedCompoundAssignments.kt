class CompoundCounter(var value: Int) {
    operator fun plusAssign(other: Int) { value = value + other }
}
class CompoundValue(val value: Int) {
    operator fun plus(other: Int): CompoundValue = CompoundValue(value + other)
}
class CompoundOwner {
    var reads = 0
    var writes = 0
    private var stored = listOf(1)
    var values: List<Int>
        get() { reads = reads + 1; return stored }
        set(value) { writes = writes + 1; stored = value }
    var number = 1
    val counter = CompoundCounter(1)
}
fun main() {
    var list: List<Int> = listOf(1, 2, 2)
    list += 3; list += listOf(4, 4)
    list -= 2; list -= arrayOf(4)
    list += sequenceOf(5, 5); list -= sequenceOf(3)
    println(list)
    var set: Set<Int> = setOf(2, 1)
    set += 1; set += arrayOf(3, 3)
    set -= listOf(2); set += sequenceOf(4, 4)
    println(set)
    val counter = CompoundCounter(1); counter += 2; println(counter.value)
    var boxed = CompoundValue(1); boxed += 2; println(boxed.value)
    val owner = CompoundOwner(); owner.values += 2; owner.values -= listOf(1)
    println(owner.reads); println(owner.writes); println(owner.values)
    owner.counter += 3; println(owner.counter.value)
    var order: List<Int> = listOf(1)
    order += if (true) { order = listOf(9); 2 } else 0
    println(order)
    var numeric = 1; numeric += if (true) { numeric = 9; 2 } else 0
    println(numeric)
    var propertyOwner = CompoundOwner(); val original = propertyOwner
    propertyOwner.values += if (true) { propertyOwner = CompoundOwner(); 2 } else 0
    println(original.values); println(propertyOwner.values)
    var numericOwner = CompoundOwner(); val originalNumeric = numericOwner
    numericOwner.number += if (true) { numericOwner = CompoundOwner(); 2 } else 0
    println(originalNumeric.number); println(numericOwner.number)
    var overflow = Int.MAX_VALUE; overflow += 1; println(overflow)
    var unsigned = UInt.MAX_VALUE; unsigned += 1u; println(unsigned)
    var text = "a"; text += "b"; println(text)
}
