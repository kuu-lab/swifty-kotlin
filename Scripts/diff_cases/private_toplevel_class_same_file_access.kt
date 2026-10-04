class Holder private constructor(msb: Long, lsb: Long) {
    companion object {
        private val state: HelperState = HelperState()

        fun describe(): String = "state=${state.x}"
    }
}

private class HelperState {
    var x: Long = 42L
}

private class Widget(val value: Int)

fun makeWidget(): Int = Widget(7).value

private class Gadget {
    val value: Int
    constructor(value: Int) {
        this.value = value
    }
}

fun makeGadget(): Int = Gadget(9).value

fun main() {
    println(Holder.describe())
    println("widget: ${makeWidget()}")
    println("gadget: ${makeGadget()}")
}
