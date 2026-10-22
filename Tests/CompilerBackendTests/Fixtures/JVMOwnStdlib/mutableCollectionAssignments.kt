import fixture.MutableCollectionOracle
class ReceiverBox { var values: List<Int> = listOf(1); var number = 1 }
class Counter(var value: Int) {
    operator fun plusAssign(other: Int) { value = value + other }
}
class Immutable(val value: Int) {
    operator fun plus(other: Int): Immutable = Immutable(value + other)
}
class AssignBox {
    var reads = 0
    var writes = 0
    private var stored = listOf(1)
    var values: List<Int>
        get() { reads = reads + 1; return stored }
        set(value) { writes = writes + 1; stored = value }
    val mutable = mutableListOf(1)
}
fun main() {
    val list = mutableListOf(1, 2, 2)
    val alias = list
    list += 2; list += listOf(3, 3)
    list -= 2; list -= listOf(3)
    println(list); println(alias === list)
    list += arrayOf(4, 4, 5); list -= arrayOf(4)
    println(list)
    list += sequenceOf(6, 6, 7); list -= sequenceOf(6)
    println(list)
    val set = mutableSetOf(3, 1, 2)
    val setAlias = set
    set += 2; set += listOf(4, 4)
    set -= 1; set -= listOf(9)
    set += arrayOf(4, 5); set -= arrayOf(3, 3)
    set += sequenceOf(5, 6); set -= sequenceOf(2, 2)
    println(set.addAll(arrayOf(7))); println(set.removeAll(arrayOf(7)))
    println(set); println(setAlias === set)
    val collection: MutableCollection<Any?> = mutableListOf(1, null)
    collection += "x"
    collection -= null
    println(collection)
    val generic: MutableCollection<Int> = mutableListOf(1)
    generic += arrayOf(2, 3); generic -= sequenceOf(2)
    println(generic)
    val result: Unit = list.plusAssign(8)
    println(result); list.minusAssign(8)
    println(list)
    println(list.addAll(listOf(8))); println(list.removeAll(listOf(8)))
    println(list.addAll(arrayOf(8, 9))); println(list.addAll(emptyArray<Int>()))
    println(list.removeAll(arrayOf(8, 9))); println(list.removeAll(emptyArray<Int>()))
    println(list.addAll(sequenceOf(8, 9))); println(list.addAll(emptySequence<Int>()))
    println(list.removeAll(sequenceOf(8, 9))); println(list.removeAll(emptySequence<Int>()))
    println(list.removeAll(listOf(99))); println(list)
    var reassigned: List<Int> = listOf(1, 2)
    reassigned += 2; reassigned += listOf(3, 3)
    reassigned += arrayOf(2, 4); reassigned -= arrayOf(2)
    reassigned += sequenceOf(5, 5); reassigned -= sequenceOf(3)
    println(reassigned)
    var reassignedSet: Set<Int> = setOf(2, 1)
    reassignedSet += 1; reassignedSet += listOf(3, 3)
    reassignedSet -= 2; reassignedSet -= listOf(9)
    reassignedSet += arrayOf(4, 4); reassignedSet -= arrayOf(1)
    reassignedSet += sequenceOf(5, 5); reassignedSet -= sequenceOf(3)
    println(reassignedSet)
    val counter = Counter(1); counter += 2; println(counter.value)
    var immutable = Immutable(1); immutable += 2; println(immutable.value)
    var number = 1; number += 2; number *= 3; println(number)
    var text = "a"; text += "b"; println(text)
    val box = AssignBox(); box.values += 2; box.values -= listOf(1)
    println(box.reads); println(box.writes); println(box.values)
    box.mutable += 2; box.mutable -= listOf(1); println(box.mutable)
    var orderList: List<Int> = listOf(1)
    orderList += if (true) { orderList = listOf(9); 2 } else 0
    println(orderList)
    var orderNumber = 1
    orderNumber += if (true) { orderNumber = 9; 2 } else 0
    println(orderNumber)
    var overflow = Int.MAX_VALUE; overflow += 1; println(overflow)
    var unsigned = UInt.MAX_VALUE; unsigned += 1u; println(unsigned)
    var receiverBox = ReceiverBox(); val originalReceiver = receiverBox
    receiverBox.values += if (true) { receiverBox = ReceiverBox(); 2 } else 0
    println(originalReceiver.values); println(receiverBox.values)
    var numericBox = ReceiverBox(); val originalNumeric = numericBox
    numericBox.number += if (true) { numericBox = ReceiverBox(); 2 } else 0
    println(originalNumeric.number); println(numericBox.number)
    val frozen = MutableCollectionOracle.frozen() as MutableCollection<Int>
    try { frozen += 3 } catch (e: UnsupportedOperationException) { println("frozen add") }
    try { frozen -= 1 } catch (e: UnsupportedOperationException) { println("frozen remove") }
    try { frozen += emptyArray<Int>() } catch (e: UnsupportedOperationException) { println("frozen empty add") }
    println(frozen.removeAll(emptyArray<Int>()))
    println(frozen.removeAll(emptySequence<Int>()))
    try { frozen.removeAll(emptyList<Int>()) } catch (e: UnsupportedOperationException) { println("frozen empty iterable remove") }
}
