package kotlin

import java.lang.Class
import kotlin.internal.KsSymbolName
import kotlin.jvm.javaPrimitiveType

// The bundled parser represents generic extension properties as zero-argument
// functions while preserving property-style member lookup. This is the
// source-backed form of Kotlin's generic Any.javaClass property.
@KsSymbolName("__kk_any_javaClass")
private external fun <T : Any> __javaClass(value: T): Class<T>

public fun <T : Any> T.javaClass(): Class<T> = __javaClass(this)

// JVM `x.javaClass` is `x.getClass()` for reference receivers but the
// primitive class literal (`int.class`, not `Integer.class`) when the
// static receiver type is a Kotlin primitive. Exact-receiver overloads keep
// boxed/`Any` receivers on the generic path above while primitive receivers
// resolve to the primitive `Class` handle shared with `X::class.java` and
// `X::class.javaPrimitiveType`.
public fun Boolean.javaClass(): Class<Boolean> = Boolean::class.javaPrimitiveType!!
public fun Byte.javaClass(): Class<Byte> = Byte::class.javaPrimitiveType!!
public fun Short.javaClass(): Class<Short> = Short::class.javaPrimitiveType!!
public fun Int.javaClass(): Class<Int> = Int::class.javaPrimitiveType!!
public fun Long.javaClass(): Class<Long> = Long::class.javaPrimitiveType!!
public fun Char.javaClass(): Class<Char> = Char::class.javaPrimitiveType!!
public fun Float.javaClass(): Class<Float> = Float::class.javaPrimitiveType!!
public fun Double.javaClass(): Class<Double> = Double::class.javaPrimitiveType!!
