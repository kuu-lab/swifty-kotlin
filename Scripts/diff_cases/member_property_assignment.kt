// KUU-1996: valid member writes retain contextual typing and setter dispatch.
class AssignmentBox<T>(var value: T)
open class AssignmentParent<T>(var inherited: T)
class AssignmentChild<T>(value: T) : AssignmentParent<T>(value)
class AssignmentPlain {
    var value: Int = 0
    var longValue: Long = 0
    var byteValue: Byte = 0
    var custom: Int = 0
        set(v) { field = v * 2 }
}

fun consume(box: AssignmentBox<in Int>) { box.value = 7 }
fun clear(box: AssignmentBox<Int?>) { box.value = null }

fun main() {
    val box = AssignmentBox(1)
    box.value = 2
    println(box.value)
    val child = AssignmentChild(3)
    child.inherited = 4
    println(child.inherited)
    val plain = AssignmentPlain()
    plain.value = 5
    plain.longValue = 6
    plain.byteValue = 127
    plain.custom = 4
    println(plain.value)
    println(plain.longValue)
    println(plain.byteValue)
    println(plain.custom)
    val wide = AssignmentBox<Any>(0)
    consume(wide)
    println(wide.value)
    val optional = AssignmentBox<Int?>(1)
    clear(optional)
    println(optional.value)
    val callback = AssignmentBox<(Int) -> Int>({ it })
    callback.value = { it + 1 }
    println(callback.value(8))
}
