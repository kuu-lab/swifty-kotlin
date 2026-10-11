import settercontrol1767.SetterBox

var receiverCalls: Int = 0
var rhsCalls: Int = 0
fun selected(box: SetterBox): SetterBox {
    receiverCalls++
    return box
}
fun nextValue(): Int {
    rhsCalls++
    return 2
}
fun main() {
    val box = SetterBox()
    box.updateBare()
    check(box.value == 10 && box.writes == 2 && box.plain == 3)
    println(box.value)
    println(box.writes)
    println(box.plain)
    box.optional = 7
    check(box.optional == 7)
    println(box.optional)
    box.optional = null
    check(box.optional == null && box.writes == 4)
    println(box.optional)
    println(box.writes)
    box.value = 3
    check(box.value == 6 && box.writes == 5)
    println(box.value)
    var rejected = false
    try { box.value = -1 } catch (failure: IllegalArgumentException) {
        check(failure.message == "negative")
        rejected = true
        println("rejected")
    }
    check(rejected && box.value == 6 && box.writes == 5)
    println(box.value)
    println(box.writes)
    selected(box).value += nextValue()
    check(box.value == 16 && box.writes == 6 && receiverCalls == 1 && rhsCalls == 1)
    println(box.value)
    println(box.writes)
    println(receiverCalls)
    println(rhsCalls)
    selected(box).counted += nextValue()
    check(box.getterCalls == 1 && box.setterCalls == 1 && receiverCalls == 2 && rhsCalls == 2)
    println(box.getterCalls)
    println(box.setterCalls)
    println(box.counted)
    println(receiverCalls)
    println(rhsCalls)
    check(box.getterCalls == 2)
}
