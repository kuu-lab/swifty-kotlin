package kotlin.text

import kswiftk.internal.*

// MARK: - String collection and sequence views (runtime-backed)

fun String.lines(): List<String> = __string_lines_flat(this)

fun String.lineSequence(): Sequence<String> = __string_lineSequence_flat(this)

fun String.asSequence(): Sequence<Char> = __string_asSequence_flat(this)

fun String.asIterable(): Iterable<Char> = __string_asIterable_flat(this)

fun String.withIndex(): Iterable<IndexedValue<Char>> = __string_withIndex_flat(this)

fun CharSequence.withIndex(): Iterable<IndexedValue<Char>> = __string_withIndex_flat(this)
