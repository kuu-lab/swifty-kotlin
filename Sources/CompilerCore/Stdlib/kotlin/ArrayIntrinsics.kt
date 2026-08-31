package kotlin

import kotlin.internal.KsSymbolName

// KSP-657: Array factory intrinsics migrated (b-reclass batch 1) from the
// synthetic stubs in
// Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticArrayStubs.swift.
//
// These are canonical Kotlin intrinsic declarations backed by the runtime ABI:
//   * `arrayOf` packs its varargs into a runtime array via `kk_array_of`
//     (the packed-array + count normalization happens in CallSupportLowerer,
//     keyed on the `kk_array_of` link name);
//   * `emptyArray` returns the shared empty array via `kk_empty_array`;
//   * `arrayOfNulls` allocates a null-filled array via `kk_array_of_nulls`.
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
