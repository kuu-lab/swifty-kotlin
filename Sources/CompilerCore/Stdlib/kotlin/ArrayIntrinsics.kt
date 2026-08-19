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

// KSP-779: Keep the primitive IntArray factory source-backed. The vararg
// parameter is represented as an IntArray, so copy its elements into the
// result allocated by the primitive-array constructor.
public inline fun intArrayOf(vararg elements: Int): IntArray {
    val result = IntArray(elements.size)
    var index = 0
    while (index < elements.size) {
        result[index] = elements[index]
        index += 1
    }
    return result
}
