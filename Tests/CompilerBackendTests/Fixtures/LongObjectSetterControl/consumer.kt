import longobjsetter.HeapBox

fun main() {
    println(HeapBox.minBytes)
    HeapBox.minBytes = 512L
    println(HeapBox.minBytes)
    HeapBox.maxBytes = 2048L
    println(HeapBox.maxBytes)
    HeapBox.doubled = 5L
    println(HeapBox.doubled)
    HeapBox.minBytes += 8L
    println(HeapBox.minBytes)
    HeapBox.flag = false
    println(HeapBox.flag)
    HeapBox.ratio = 0.5
    println(HeapBox.ratio)
    println(HeapBox.plainLong)
    HeapBox.plainLong = 77L
    println(HeapBox.plainLong)
    HeapBox.silentA = 9L
    HeapBox.silentB = 11L
    println(HeapBox.silentA)
    println(HeapBox.silentB)
    println(HeapBox.minBytes)
}
