@file:kotlin.jvm.JvmName("StandardKt")
package kotlin

public inline fun repeat(times: Int, action: (Int) -> Unit) {
    var index = 0
    while (index < times) {
        action(index)
        index += 1
    }
}

public inline fun <T, R> T.let(block: (T) -> R): R = block(this)

public inline fun <T, R> T.run(block: T.() -> R): R = block()

public inline fun <R> run(block: () -> R): R = block()

public inline fun <T> T.apply(block: T.() -> Unit): T {
    block()
    return this
}

public inline fun <T, R> with(receiver: T, block: T.() -> R): R {
    return receiver.block()
}

public inline fun <T> T.also(block: (T) -> Unit): T {
    block(this)
    return this
}
