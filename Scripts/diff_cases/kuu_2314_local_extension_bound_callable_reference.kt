// KUU-2314: An explicit bound callable reference can target a local extension
// and captures the receiver for the extension body.

class Host { val text = "OK" }

fun box(): String {
    fun Host.label() = text
    val label = Host()::label
    return label()
}

fun main() {
    print(box())
}
