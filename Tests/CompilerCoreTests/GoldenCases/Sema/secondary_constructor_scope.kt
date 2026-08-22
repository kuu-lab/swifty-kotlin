package golden.sema

class Widget {
    var label: String

    constructor(name: String) {
        label = name
    }

    constructor(name: String, suffix: String) {
        label = name + suffix
    }
}

fun main() {
    val w1 = Widget("a")
    val w2 = Widget("a", "b")
}
