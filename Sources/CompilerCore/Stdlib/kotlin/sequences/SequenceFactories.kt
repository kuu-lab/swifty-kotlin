package kotlin.sequences

import kotlin.internal.KsSymbolName

// MIGRATION-SEQ-001 / KSP-651
// Sequence factory APIs are source-backed. The runtime entries remain private
// implementation bridges for lazy traversal and packed vararg arrays.

@KsSymbolName("__kk_empty_sequence")
private external fun <T> __kkEmptySequence(): Sequence<T>

@KsSymbolName("__kk_sequence_of")
private external fun <T> __kkSequenceOf(elements: Any?): Sequence<T>

@KsSymbolName("__kk_sequence_generate")
private external fun <T : Any> __kkSequenceGenerate(
    seed: T,
    nextFunction: (T) -> T?
): Sequence<T>

@KsSymbolName("__kk_sequence_generate_noarg")
private external fun <T : Any> __kkSequenceGenerateNoArg(
    nextFunction: () -> T?
): Sequence<T>

public fun <T> emptySequence(): Sequence<T> = __kkEmptySequence()

public fun <T> sequenceOf(vararg elements: T): Sequence<T> = __kkSequenceOf(elements)

public fun <T : Any> generateSequence(seed: T?, nextFunction: (T) -> T?): Sequence<T> {
    val nonNullSeed = seed ?: return emptySequence<T>()
    return __kkSequenceGenerate(nonNullSeed, nextFunction)
}

public fun <T : Any> generateSequence(
    seedFunction: () -> T?,
    nextFunction: (T) -> T?
): Sequence<T> {
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> {
            val seed = seedFunction()
            val nonNullSeed = seed ?: return emptySequence<T>().iterator()
            return __kkSequenceGenerate(nonNullSeed, nextFunction).iterator()
        }
    }
}

public fun <T : Any> generateSequence(nextFunction: () -> T?): Sequence<T> =
    __kkSequenceGenerateNoArg(nextFunction).constrainOnce()

// Preserve Kotlin's bottom-type inference for a producer that immediately
// returns null. The generic overload cannot infer its non-null T from null.
public fun generateSequence(nextFunction: () -> Nothing?): Sequence<Nothing> =
    emptySequence()
