@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package kotlin

import kotlin.internal.KsSymbolName

// KUU-3537: `Array` and the signed primitive arrays implement `Cloneable`,
// matching the JVM where every array type is `java.lang.Cloneable`. The
// unsigned arrays stay off the list: on the JVM they are value classes over
// the signed arrays and are *not* Cloneable.
public class Array<T> private constructor() : Cloneable {
    public operator fun get(index: Int): T = this[index]
    public operator fun set(index: Int, value: T) { this[index] = value }
}

public class BooleanArray private constructor() : Cloneable {
    public operator fun get(index: Int): Boolean = this[index]
    public operator fun set(index: Int, value: Boolean) { this[index] = value }
}
public class ByteArray private constructor() : Cloneable {
    public operator fun get(index: Int): Byte = this[index]
    public operator fun set(index: Int, value: Byte) { this[index] = value }
}
public class CharArray private constructor() : Cloneable {
    public operator fun get(index: Int): Char = this[index]
    public operator fun set(index: Int, value: Char) { this[index] = value }
}
public class DoubleArray private constructor() : Cloneable {
    public operator fun get(index: Int): Double = this[index]
    public operator fun set(index: Int, value: Double) { this[index] = value }
}
public class FloatArray private constructor() : Cloneable {
    public operator fun get(index: Int): Float = this[index]
    public operator fun set(index: Int, value: Float) { this[index] = value }
}
public class IntArray private constructor() : Cloneable {
    public operator fun get(index: Int): Int = this[index]
    public operator fun set(index: Int, value: Int) { this[index] = value }
}
public class LongArray private constructor() : Cloneable {
    public operator fun get(index: Int): Long = this[index]
    public operator fun set(index: Int, value: Long) { this[index] = value }
}
public class ShortArray private constructor() : Cloneable {
    public operator fun get(index: Int): Short = this[index]
    public operator fun set(index: Int, value: Short) { this[index] = value }
}
@ExperimentalUnsignedTypes
public class UByteArray private constructor() {
    public operator fun get(index: Int): UByte = this[index]
    public operator fun set(index: Int, value: UByte) { this[index] = value }
}
@ExperimentalUnsignedTypes
public class UShortArray private constructor() {
    public operator fun get(index: Int): UShort = this[index]
    public operator fun set(index: Int, value: UShort) { this[index] = value }
}
@ExperimentalUnsignedTypes
public class UIntArray private constructor() {
    public operator fun get(index: Int): UInt = this[index]
    public operator fun set(index: Int, value: UInt) { this[index] = value }
}
@ExperimentalUnsignedTypes
public class ULongArray private constructor() {
    public operator fun get(index: Int): ULong = this[index]
    public operator fun set(index: Int, value: ULong) { this[index] = value }
}

@KsSymbolName("kk_array_of")
public external fun <T> arrayOf(vararg elements: T): Array<T>

@KsSymbolName("kk_empty_array")
public external fun <T> emptyArray(): Array<T>

@KsSymbolName("kk_array_of_nulls")
public external fun <T> arrayOfNulls(size: Int): Array<T?>

public inline fun <reified T : Any> Array<*>.isArrayOf(): Boolean =
    throw IllegalStateException("isArrayOf is expanded by the compiler")

// KSP-779: Keep primitive vararg packing on the raw runtime path so Int
// elements are not boxed into a temporary container before array creation.
@KsSymbolName("kk_array_of")
public external fun intArrayOf(vararg elements: Int): IntArray

@KsSymbolName("__kk_intArray_size")
internal external fun __kkIntArraySize(array: IntArray): Int

@KsSymbolName("__kk_longArray_size")
internal external fun __kkLongArraySize(array: LongArray): Int

@KsSymbolName("__kk_shortArray_size")
internal external fun __kkShortArraySize(array: ShortArray): Int

@KsSymbolName("__kk_byteArray_size")
internal external fun __kkByteArraySize(array: ByteArray): Int

@KsSymbolName("__kk_charArray_size")
internal external fun __kkCharArraySize(array: CharArray): Int

@KsSymbolName("__kk_booleanArray_size")
internal external fun __kkBooleanArraySize(array: BooleanArray): Int

@KsSymbolName("__kk_doubleArray_size")
internal external fun __kkDoubleArraySize(array: DoubleArray): Int

@KsSymbolName("__kk_floatArray_size")
internal external fun __kkFloatArraySize(array: FloatArray): Int

@KsSymbolName("__kk_array_size")
internal external fun __kkArraySize(array: Array<*>): Int

@KsSymbolName("__kk_uByteArray_size")
internal external fun __kkUByteArraySize(array: UByteArray): Int

@KsSymbolName("__kk_uShortArray_size")
internal external fun __kkUShortArraySize(array: UShortArray): Int

@KsSymbolName("__kk_uIntArray_size")
internal external fun __kkUIntArraySize(array: UIntArray): Int

@KsSymbolName("__kk_uLongArray_size")
internal external fun __kkULongArraySize(array: ULongArray): Int
