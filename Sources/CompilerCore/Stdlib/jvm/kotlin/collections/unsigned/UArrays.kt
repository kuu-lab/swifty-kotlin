package kotlin.collections.unsigned

import kotlin.collections.ArrayIndexingIterable

@ExperimentalUnsignedTypes
public fun UByteArray.withIndex(): Iterable<IndexedValue<UByte>> = ArrayIndexingIterable(size) { this[it] }
@ExperimentalUnsignedTypes
public fun UShortArray.withIndex(): Iterable<IndexedValue<UShort>> = ArrayIndexingIterable(size) { this[it] }
@ExperimentalUnsignedTypes
public fun UIntArray.withIndex(): Iterable<IndexedValue<UInt>> = ArrayIndexingIterable(size) { this[it] }
@ExperimentalUnsignedTypes
public fun ULongArray.withIndex(): Iterable<IndexedValue<ULong>> = ArrayIndexingIterable(size) { this[it] }
