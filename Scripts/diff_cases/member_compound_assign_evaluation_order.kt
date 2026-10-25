// Property compound assignment reads the target before evaluating an RHS
// that can mutate the same property, including accessor-backed virtual members.
var events = ""

class Box(var n: Int)

fun plainRhs(box: Box): Int {
    box.n = 20
    return 2
}

class CustomBox(initial: Int) {
    private var storage = initial

    var n: Int
        get() {
            events += "G"
            return storage
        }
        set(value) {
            events += "S"
            storage = value
        }

    fun current(): Int = storage
}

fun customRhs(box: CustomBox): Int {
    box.n = 20
    events += "R"
    return 2
}

open class BaseBox(initial: Int) {
    protected var storage = initial

    open var n: Int
        get() {
            events += "g"
            return storage
        }
        set(value) {
            events += "s"
            storage = value
        }

    fun current(): Int = storage
}

class DerivedBox(initial: Int) : BaseBox(initial) {
    override var n: Int
        get() {
            events += "G"
            return super.n
        }
        set(value) {
            events += "S"
            super.n = value
        }
}

fun virtualRhs(box: BaseBox): Int {
    box.n = 20
    events += "R"
    return 2
}

fun compoundVirtual(box: BaseBox) {
    box.n += virtualRhs(box)
}

fun main() {
    val plain = Box(10)
    plain.n += plainRhs(plain)
    println(plain.n)

    events = ""
    val custom = CustomBox(10)
    custom.n += customRhs(custom)
    println(custom.current())
    println(events)

    events = ""
    val derived = DerivedBox(10)
    compoundVirtual(derived)
    println(derived.current())
    println(events)
}
