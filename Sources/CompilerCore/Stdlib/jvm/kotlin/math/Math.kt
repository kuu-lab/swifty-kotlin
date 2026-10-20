@file:kotlin.jvm.JvmName("MathKt")
package kotlin.math

import kotlin.jvm.internal.__jvmMinDouble
import kotlin.jvm.internal.__jvmMaxDouble
import kotlin.jvm.internal.__jvmMinFloat
import kotlin.jvm.internal.__jvmMaxFloat

public fun min(a: Int, b: Int): Int = if (a <= b) a else b
public fun max(a: Int, b: Int): Int = if (a >= b) a else b
public fun min(a: Long, b: Long): Long = if (a <= b) a else b
public fun max(a: Long, b: Long): Long = if (a >= b) a else b
public fun min(a: Double, b: Double): Double = __jvmMinDouble(a, b)
public fun max(a: Double, b: Double): Double = __jvmMaxDouble(a, b)
public fun min(a: Float, b: Float): Float = __jvmMinFloat(a, b)
public fun max(a: Float, b: Float): Float = __jvmMaxFloat(a, b)
