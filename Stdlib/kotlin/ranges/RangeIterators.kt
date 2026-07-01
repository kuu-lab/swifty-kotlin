package kotlin.ranges

// MIGRATION-RANGE-001
// iterator() for IntRange, LongRange, CharRange, IntProgression, LongProgression,
// CharProgression.
// Migration source: Sources/Runtime/RuntimeRangeAndDispatch.swift
//   (kk_range_iterator, kk_range_hasNext, kk_range_next)
//   Sources/Runtime/RuntimeRangeLongRange.swift (kk_long_range_iterator)
// See RangeMembership.kt for the contains()/isEmpty() half of this migration,
// including the fuller note on the parallel Sema/KIR dispatch paths that still
// own every call site.
//
// NOTE: Not yet wired into the compiler pipeline (see RangeMembership.kt).
// `for (x in range)` does not even go through `.iterator()` today: it is
// special-cased in ExprLowerer+ControlFlowAndBlocks.swift straight to the
// kk_*range_iterator/kk_iterator_hasNext/kk_iterator_next runtime calls. The
// functions below exist for the explicit `range.iterator()` call surface
// (Iterable<T> conformance) and as the eventual replacement for that lowering.
//
// Implementation note — why this delegates through toList() instead of a
// hand-written lazy iterator: a user-defined class that implements the
// built-in kotlin.collections.Iterator<T> compiles, but the compiler currently
// rejects using it *polymorphically* as Iterator<T> (assigning it to an
// Iterator<T>-typed val, returning it from a function declared to return
// Iterator<T>, etc. all fail with "No viable overload found for call"; this
// reproduces the same way for both primitive and reference element types, so
// it isn't specific to these six classes). Confirmed working today: iterators
// obtained from already-native sources — e.g. List<T>.iterator() — behave
// correctly as Iterator<T>. toList() is itself a real (if not-yet-wired)
// member on all six classes (see HeaderHelpers+SyntheticTypedRangeStubs.swift /
// HeaderHelpers+SyntheticRangeProgressionStubs.swift), so this is written in
// terms of another already-Kotlin-visible member rather than a native bridge.
// Once custom Iterator<T> implementors work polymorphically, the right
// long-term shape is a lazy per-family iterator class (mirroring upstream
// Kotlin's IntProgressionIterator/LongProgressionIterator/
// CharProgressionIterator) instead of eagerly materialising every element.

public operator fun IntRange.iterator(): Iterator<Int> = this.toList().iterator()
public operator fun IntProgression.iterator(): Iterator<Int> = this.toList().iterator()
public operator fun LongRange.iterator(): Iterator<Long> = this.toList().iterator()
public operator fun LongProgression.iterator(): Iterator<Long> = this.toList().iterator()
public operator fun CharRange.iterator(): Iterator<Char> = this.toList().iterator()
public operator fun CharProgression.iterator(): Iterator<Char> = this.toList().iterator()
