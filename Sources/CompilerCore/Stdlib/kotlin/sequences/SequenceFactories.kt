package kotlin.sequences

import kotlin.internal.KsSymbolName

// MIGRATION-SEQ-001 / KSP-651 / KSP-1338
// Sequence factory APIs are source-backed. The runtime entries remain private
// implementation bridges for lazy traversal, packed vararg arrays, and the
// sequence/iterator builder suspension points.

@KsSymbolName("__kk_empty_sequence")
private external fun <T> __kkEmptySequence(): Sequence<T>

@KsSymbolName("__kk_sequence_of")
private external fun <T> __kkSequenceOf(elements: Any?): Sequence<T>

@KsSymbolName("kk_sequence_of_single")
private external fun <T> __kkSequenceOfSingle(element: T): Sequence<T>

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

// Parameter is not named `iterator` so the object override does not recurse.
@kotlin.internal.InlineOnly
public inline fun <T> Sequence(crossinline iteratorProducer: () -> Iterator<T>): Sequence<T> =
    object : Sequence<T> {
        override fun iterator(): Iterator<T> = iteratorProducer()
    }

public fun <T> sequenceOf(vararg elements: T): Sequence<T> = __kkSequenceOf(elements)

@SinceKotlin("2.2")
public fun <T> sequenceOf(element: T): Sequence<T> = __kkSequenceOfSingle(element)

@SinceKotlin("2.2")
@kotlin.internal.InlineOnly
public inline fun <T> sequenceOf(): Sequence<T> = emptySequence()

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

// KSP-1338: public sequence/iterator builders stay on the existing runtime
// suspension bridges. Source declarations replace the synthetic stubs so the
// Kotlin 2.3.10 signatures resolve through bundled stdlib.
@SinceKotlin("1.3")
@KsSymbolName("__kk_sequence_builder_build")
public external fun <T> sequence(
    block: suspend SequenceScope<T>.() -> Unit
): Sequence<T>

@SinceKotlin("1.3")
@KsSymbolName("__kk_iterator_builder_build")
public external fun <T> iterator(
    block: suspend SequenceScope<T>.() -> Unit
): Iterator<T>
