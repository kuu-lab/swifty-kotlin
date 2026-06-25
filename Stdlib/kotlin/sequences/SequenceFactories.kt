package kotlin.sequences

// MIGRATION-SEQ-001
// Sequence factory functions: sequenceOf, emptySequence, generateSequence, sequence { } builder.
// Migration source:
//   Sources/Runtime/RuntimeSequence.swift
//     (kk_empty_sequence, kk_sequence_of, kk_sequence_generate, kk_sequence_generate_noarg)
//   Sources/Runtime/RuntimeSequenceBuilders.swift
//     (kk_sequence_builder_yield, kk_sequence_builder_yieldAll, kk_sequence_builder_build)
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// CollectionLiteralLoweringPass intercepts all factory call sites and rewrites them to kk_* ABI
// calls (CollectionLiteralLoweringPass+CallRewriteFactories.swift lines 505-603 and
// CollectionLiteralLoweringPass+CallRewriteSequenceBuilders.swift). The synthetic stubs in
// HeaderHelpers+SyntheticTODOAndIOStubs.swift and
// HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift continue to provide type information
// until this file is loaded. Wiring (and removal of those stubs) happens in RF-STDLIB-004+.
//
// Implementation strategy:
//   - emptySequence<T>()                  — ABI bridge to kk_empty_sequence
//   - sequenceOf(vararg elements: T)      — ABI bridge to kk_sequence_of (passes vararg array)
//   - generateSequence(seed, nextFn)      — ABI bridge to kk_sequence_generate
//   - generateSequence(nextFn)            — ABI bridge to kk_sequence_generate_noarg
//   - SequenceScope / sequence { }        — pure Kotlin (kk_sequence_builder_build takes a
//                                           compiled function pointer, not a Kotlin-level lambda)

// ─── ABI bridges ─────────────────────────────────────────────────────────────
//
// These map directly to @_cdecl functions in RuntimeSequence.swift and
// RuntimeSequenceBuilders.swift. Parameter types use Any? for opaque handles;
// the UNCHECKED_CAST suppression covers the cast back to typed Sequence<T>.

private external fun kk_empty_sequence(): Sequence<Nothing>

@Suppress("UNCHECKED_CAST")
private external fun kk_sequence_of(array: Any?): Sequence<Nothing>

@Suppress("UNCHECKED_CAST")
private external fun kk_sequence_generate(seed: Any?, nextFunction: Any?): Sequence<Nothing>

@Suppress("UNCHECKED_CAST")
private external fun kk_sequence_generate_noarg(nextFunction: Any?): Sequence<Nothing>

// ─── emptySequence ───────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
public fun <T> emptySequence(): Sequence<T> = kk_empty_sequence() as Sequence<T>

// ─── sequenceOf ──────────────────────────────────────────────────────────────

public fun <T> sequenceOf(vararg elements: T): Sequence<T> {
    if (elements.size == 0) return emptySequence()
    @Suppress("UNCHECKED_CAST")
    return kk_sequence_of(elements) as Sequence<T>
}

// ─── generateSequence ────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
public fun <T : Any> generateSequence(seed: T?, nextFunction: (T) -> T?): Sequence<T> =
    kk_sequence_generate(seed, nextFunction) as Sequence<T>

@Suppress("UNCHECKED_CAST")
public fun <T : Any> generateSequence(nextFunction: () -> T?): Sequence<T> =
    kk_sequence_generate_noarg(nextFunction) as Sequence<T>

// ─── SequenceScope ───────────────────────────────────────────────────────────
//
// Receiver type for the sequence { } builder DSL. yield() and yieldAll() are
// lowered to kk_sequence_builder_yield / kk_sequence_builder_yieldAll by
// CollectionLiteralLoweringPass while this file is not yet wired in.
// Once wired (RF-STDLIB-004+) the abstract methods below run directly.

public abstract class SequenceScope<in T> {
    public abstract fun yield(value: T)
    public abstract fun yieldAll(elements: Iterator<T>)
    public abstract fun yieldAll(elements: Iterable<T>)
    public abstract fun yieldAll(sequence: Sequence<T>)
}

// ─── sequence { } builder ────────────────────────────────────────────────────
//
// Like buildList / buildSet / buildMap (MIGRATION-COL-011), the runtime entry
// point kk_sequence_builder_build receives a compiled function pointer and
// cannot be called via a private external declaration. The pure Kotlin body
// below is the correct migration target: it runs the block synchronously
// against a collecting SequenceScope, then wraps the accumulated elements in
// a generateSequence call so the returned Sequence<T> is correctly typed.

public fun <T> sequence(block: SequenceScope<T>.() -> Unit): Sequence<T> {
    val elements = mutableListOf<T>()
    val scope = object : SequenceScope<T>() {
        override fun yield(value: T) {
            elements.add(value)
        }
        override fun yieldAll(elements: Iterator<T>) {
            while (elements.hasNext()) this.elements.add(elements.next())
        }
        override fun yieldAll(elements: Iterable<T>) {
            val it = elements.iterator()
            while (it.hasNext()) this.elements.add(it.next())
        }
        override fun yieldAll(sequence: Sequence<T>) {
            val it = sequence.iterator()
            while (it.hasNext()) this.elements.add(it.next())
        }
    }
    scope.block()
    var i = 0
    return generateSequence { if (i < elements.size) elements[i++] else null }
}
