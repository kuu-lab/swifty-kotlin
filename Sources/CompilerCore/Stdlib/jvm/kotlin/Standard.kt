@file:kotlin.jvm.JvmName("StandardKt")
package kotlin

public inline fun <T> T.also(block: (T) -> Unit): T {
    block(this)
    return this
}
