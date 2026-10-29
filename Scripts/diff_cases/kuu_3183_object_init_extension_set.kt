var result = "fail"

fun <T, R> myWith(receiver: T, block: T.() -> R): R = receiver.block()

object Foo2 {
    operator fun Any?.get(key: String) = "OK"
    operator fun Any?.set(key: String, value: String) {
        result = value
    }
}

object Main {
    fun bar() = myWith(Foo2) {
        val x = object {
            init {
                38["Hello!"] = "OK"
            }
        }
        result
    }
}

fun box(): String = Main.bar()

fun main() {
    println(box())
}
