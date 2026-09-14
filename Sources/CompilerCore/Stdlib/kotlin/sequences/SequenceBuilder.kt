package kotlin.sequences

import kotlin.internal.KsSymbolName

// KSP-1519: sequence {} / iterator {} builder entry points. The suspension
// points (yield/yieldAll on SequenceScope) remain compiler/runtime-owned
// through the CollectionLiteralLoweringPass name rewrite (see SequenceScope.kt);
// only the two top-level factory functions are declared here.

@KsSymbolName("__kk_sequence_builder_build")
public external fun <T> sequence(block: suspend SequenceScope<T>.() -> Unit): Sequence<T>

@KsSymbolName("__kk_iterator_builder_build")
public external fun <T> iterator(block: suspend SequenceScope<T>.() -> Unit): Iterator<T>
