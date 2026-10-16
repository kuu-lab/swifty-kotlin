// KUU-2250: A getter's backing field stays tied to its owning instance in lambdas.
fun <T> eval(fn: () -> T) = fn()

class My {
    val my: String = "O"
        get() = eval { field } + "K"
}

fun box() = My().my

class C {
    val payload: String = "O"
        get() = eval { field } + "K"
}

fun minimalBox(): String = C().payload

class CaptureBox(initial: String) {
    val payload: String = initial
        get() = eval { field } + "K"

    val shadowedReceiver: String = initial
        get() = with(CaptureBox("WRONG")) { eval { field } } + "K"

    val direct: String = initial
        get() = field

    val localCapture: String = initial
        get() {
            val stored = field
            return eval { stored } + "K"
        }

    val marker: String = "member"
    val memberCapture: String
        get() = eval { marker }
}

fun main() {
    println(box())
    println(minimalBox())
    val box = CaptureBox("O")
    println(box.payload)
    println(box.shadowedReceiver)
    println(box.direct)
    println(box.localCapture)
    println(box.memberCapture)
}
