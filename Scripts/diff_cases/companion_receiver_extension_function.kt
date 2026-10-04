class Widget(val id: Int) {
    companion object
}

fun Widget.Companion.create(id: Int): Widget = Widget(id)

class Counter {
    companion object Factory {
        var count: Int = 0
    }
}

fun Counter.Factory.increment(): Int {
    count += 1
    return count
}

fun main() {
    val w = Widget.create(7)
    println(w.id)

    println(Counter.increment())
    println(Counter.increment())
    println(Counter.count)
}
