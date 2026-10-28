@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package kotlin

import kotlin.internal.KsSymbolName

// KSP-1517: `Array<T>` and the primitive array types use intrinsic construction
// (`IntArray(size)`), indexing (`array[i]`), `.size`, and the
// HOF surface are all resolved by compiler name matching (see
// `CompilerKnownNames.isArrayLikeName`/`isPrimitiveArrayConstructorTypeName`
// and `PrimitiveArrayFactoryPredicates.swift`). Source-backed get/set declarations
// expose explicit calls as well as indexing, while their bodies still use the
// compiler's intrinsic indexed-access lowering. Runtime storage is the single untyped `RuntimeArrayBox`
// (`RuntimeArrayBasics.swift`) for every primitive kind, so these shells stay
// with a private constructor, matching the `Nothing`/
// `DeepRecursiveScope` pattern for compiler-intrinsic-backed types that are
// never constructed through their own declared constructor. Predeclared early
// via `predeclareBundledArrayHeaders` (`HeaderCollection.swift`) because
// array-typed synthetic signatures (e.g. `MutableCollection<T>.addAll`) are
// registered before the normal bundled header collection pass; the fallback
// fires when the sole synthetic anchor is needed instead (`--no-stdlib` /
// precompiled `.kklib`, no bundled source parsed).
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

//   * `arrayOf` packs its varargs into a runtime array via `kk_array_of`
//     (the packed-array + count normalization happens in CallSupportLowerer,
//     keyed on the `kk_array_of` link name);
//   * `emptyArray` allocates a fresh array and tags its component at the typed
//     call site; `kk_empty_array` remains the untyped runtime fallback.
@KsSymbolName("kk_array_of")
public external fun <T> arrayOf(vararg elements: T): Array<T>

@KsSymbolName("kk_empty_array")
public external fun <T> emptyArray(): Array<T>

@KsSymbolName("kk_array_of_nulls")
public external fun <T> arrayOfNulls(size: Int): Array<T?>

// KSP-779: Keep primitive vararg packing on the raw runtime path so Int
// elements are not boxed into a temporary container before array creation.
@KsSymbolName("kk_array_of")
public external fun intArrayOf(vararg elements: Int): IntArray

// KSP-1512: signed primitive-array `size` remains a runtime-backed intrinsic
// behind the public Kotlin extension properties in ArrayConversions.kt.
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

// KSP-1513: generic and unsigned array `size` bridges. The public members are
// declared in bundled Kotlin source; these declarations retain only the
// runtime storage access.
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
