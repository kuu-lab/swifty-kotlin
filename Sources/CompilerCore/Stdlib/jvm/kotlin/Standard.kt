@file:kotlin.jvm.JvmName("StandardKt")
package kotlin

public inline fun repeat(times: Int, action: (Int) -> Unit) {
    var index = 0
    while (index < times) {
        action(index)
        index += 1
    }
}

public inline fun <T> T.also(block: (T) -> Unit): T {
    block(this)
    return this
}
