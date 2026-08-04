package kotlin.text

// CharSequence.chunked(size, transform) / .windowed(size, step, partialWindows, transform) —
// the List<R>-returning overloads, as opposed to the already-migrated chunkedSequence /
// windowedSequence — had no registered overload at all, so the trailing transform lambda's
// implicit `it` never bound (KSWIFTK-SEMA-0022 "Unresolved reference 'it'"). Implemented here
// directly rather than via a new native ABI bridge, mirroring this codebase's existing
// Iterable<T> migration (Stdlib/kotlin/collections/ListWindowChunk.kt). Indices go through
// toString().toList() like subSequence/substring in StringSubstringSlice.kt, since a flat
// CharSequence's raw `length` observes UTF-8 byte length rather than character count.
//
// Unlike ListWindowChunk.kt, `chunked` does NOT delegate to `windowed` here (real kotlinc's
// own stdlib does: `chunked(size, transform) = windowed(size, size, true, transform)`) — a
// generic bundled-source function forwarding its own function-typed parameter to another
// generic bundled-source function fails to link (KIR call lowering never discovers the callee
// as reachable and never emits its body; confirmed independent of these two functions with a
// minimal two-function repro). Each function is self-contained until that's root-caused.
//
// The loop keeps advancing by `step` while `index < length` alone (not stopping at the first
// partial/short window): when `step` is smaller than `size`, more than one trailing partial
// window can occur (e.g. "hi".windowed(100, 1, true) is [2, 1], not just [2]) — matches real
// kotlinc's `while (index in 0 until thisSize)` shape.

internal fun <R> CharSequence.kswiftkWindowedTransform(
    size: Int,
    step: Int,
    partialWindows: Boolean,
    transform: (CharSequence) -> R
): List<R> {
    val length = this.toString().toList().size
    val safeSize = if (size > 0) size else 1
    val safeStep = if (step > 0) step else 1
    val result = ArrayList<R>()
    var index = 0
    while (index < length) {
        val end = index + safeSize
        if (end > length) {
            if (partialWindows) {
                result.add(transform(this.subSequence(index, length)))
            }
        } else {
            result.add(transform(this.subSequence(index, end)))
        }
        index += safeStep
    }
    return result
}

internal fun <R> CharSequence.kswiftkChunkedTransform(size: Int, transform: (CharSequence) -> R): List<R> {
    val length = this.toString().toList().size
    val safeSize = if (size > 0) size else 1
    val result = ArrayList<R>()
    var index = 0
    while (index < length) {
        val end = index + safeSize
        if (end > length) {
            result.add(transform(this.subSequence(index, length)))
        } else {
            result.add(transform(this.subSequence(index, end)))
        }
        index += safeSize
    }
    return result
}
