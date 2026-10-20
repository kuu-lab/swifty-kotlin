@file:kotlin.jvm.JvmName("NumbersKt")
package kotlin

public inline fun Double.isNaN(): Boolean = this != this
public inline fun Float.isNaN(): Boolean = this != this

public inline fun Double.isInfinite(): Boolean = this == Double.POSITIVE_INFINITY || this == Double.NEGATIVE_INFINITY
public inline fun Float.isInfinite(): Boolean = this == Float.POSITIVE_INFINITY || this == Float.NEGATIVE_INFINITY

public inline fun Double.isFinite(): Boolean = this == this && this != Double.POSITIVE_INFINITY && this != Double.NEGATIVE_INFINITY
public inline fun Float.isFinite(): Boolean = this == this && this != Float.POSITIVE_INFINITY && this != Float.NEGATIVE_INFINITY
