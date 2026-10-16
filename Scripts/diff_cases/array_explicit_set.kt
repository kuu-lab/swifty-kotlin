package array_test

fun box(): String {
    var array: IntArray? = IntArray(10)
    array?.set(0, 3)
    if (array?.get(0) != 3) return "fail"

    var a = arrayOfNulls<Array<String?>>(5)
    var b = arrayOfNulls<String>(1)
    b.set(0, "239")
    a?.set(0, b)
    if (a?.get(0)?.get(0) != "239") return "fail"
    return "OK"
}

fun indexedWriteControl(): String {
    val generic = arrayOfNulls<String>(1)
    generic[0] = "indexed"
    val primitive = IntArray(1)
    primitive[0] = 7
    return "${generic.get(0)}:${primitive.get(0)}"
}

data class Point(val row: Int)

operator fun Array<CharArray>.set(point: Point, value: Char) {
    this[point.row][0] = value
}

fun pointSetterControl(): String {
    val nested = arrayOf(charArrayOf('?'))
    nested.set(Point(0), 'x')
    return nested.get(0).get(0).toString()
}

var setterEvents = ""
var extensionTarget = intArrayOf(0)

fun newExtensionTarget(): IntArray {
    setterEvents += "r"
    return extensionTarget
}

fun nextLongIndex(): Long {
    setterEvents += "i"
    return 0L
}

fun nextIntValue(): Int {
    setterEvents += "v"
    return 9
}

operator fun IntArray.set(index: Long, value: Int) {
    setterEvents += "s"
    this[index.toInt()] = value
}

fun extensionSetterControl(): String {
    setterEvents = ""
    extensionTarget = intArrayOf(0)
    newExtensionTarget().set(nextLongIndex(), nextIntValue())
    return "$setterEvents:${extensionTarget.get(0)}"
}

fun main() {
    println(box())
    println(indexedWriteControl())
    println(pointSetterControl())
    println(extensionSetterControl())
}
