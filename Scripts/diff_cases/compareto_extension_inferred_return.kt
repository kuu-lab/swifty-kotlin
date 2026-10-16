// KUU-2213: Based on Kotlin 2.3.10's operatorConventions/compareTo/extensionArray.kt.
fun checkLess(x: Array<Int>, y: Array<Int>) = when {
    x >= y    -> "Fail $x >= $y"
    !(x < y)  -> "Fail !($x < $y)"
    !(x <= y) -> "Fail !($x <= $y)"
    x > y     -> "Fail $x > $y"
    x.compareTo(y) >= 0 -> "Fail $x.compareTo($y) >= 0"
    else -> "OK"
}

operator fun Array<Int>.compareTo(other: Array<Int>) = size - other.size

fun box(): String {
    val a = arrayOfNulls<Int>(0) as Array<Int>
    val b = arrayOfNulls<Int>(1) as Array<Int>
    return checkLess(a, b)
}

class Item(val size: Int)
fun itemCheck(x: Item, y: Item) = when {
    x <= y -> "OK"
    x > y -> "FAIL"
    else -> "FAIL"
}
operator fun Item.compareTo(other: Item) = size - other.size

class ExplicitItem(val size: Int)
fun explicitItemCheck(x: ExplicitItem, y: ExplicitItem) = x <= y
operator fun ExplicitItem.compareTo(other: ExplicitItem): Int = size - other.size

class PriorItem(val size: Int)
operator fun PriorItem.compareTo(other: PriorItem) = size - other.size
fun priorItemCheck(x: PriorItem, y: PriorItem) = x <= y

fun callLater(): Int = inferredLater()
fun inferredLater() = 42

fun main() {
    println(box())
    println(itemCheck(Item(1), Item(2)))
    println(explicitItemCheck(ExplicitItem(1), ExplicitItem(2)))
    println(priorItemCheck(PriorItem(1), PriorItem(2)))
    println(callLater())
}
