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
