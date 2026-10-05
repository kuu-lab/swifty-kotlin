// KUU-1189: stored KProperty objects must dispatch invoke, not execute their heap address.
class Box(val value: Int, val text: String, var mutable: Int)

fun main() {
    val property = Box::value
    val boxes = listOf(Box(1, "one", 4), Box(2, "two", 5))
    println(property.get(Box(3, "three", 6)))
    println(boxes.map(property))
    println(boxes.asSequence().map(property).toList())

    val length = String::length
    println(listOf("", "abc", "hello").map(length))
    val text = Box::text
    println(boxes.map(text))
    val mutable = Box::mutable
    println(boxes.map(mutable))
    mutable.set(boxes[0], 8)
    println(boxes.map(mutable))

    val bound = boxes[0]::value
    println(bound())
    println(listOf(bound, boxes[1]::value).map { it() })
    val direct: (Box) -> Int = Box::value
    val offset = 10
    val captured: (Box) -> Int = { it.value + offset }
    println(boxes.map(direct))
    println(boxes.map(captured))
}
