@file:kotlin.jvm.JvmName("NumbersKt")
package kotlin

public fun Double.isNaN(): Boolean = this != this
public fun Float.isNaN(): Boolean = this != this
