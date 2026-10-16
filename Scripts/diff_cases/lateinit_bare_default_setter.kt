// KUU-2452: A bare default setter must not become part of a lateinit property's type.
class App {
    val context: Context = Context()

    fun onCreate() {
        instance = this
    }

    companion object {
        private lateinit var instance: App set
        val context: Context get() = instance.context
    }
}

class Context {
    fun print(): String = "OK"
}

fun box(): String {
    val app = App()
    app.onCreate()
    return App.context.print()
}

class Holder(val text: String) {
    fun install() { instance = this }

    companion object {
        private lateinit var instance: Holder set
        val value: String get() = instance.text
    }
}

fun minimalBox(): String {
    val holder = Holder("OK")
    holder.install()
    return Holder.value
}

fun main() {
    println(box())
    println(minimalBox())
}
