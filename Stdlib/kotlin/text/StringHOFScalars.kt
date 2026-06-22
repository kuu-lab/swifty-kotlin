package kotlin.text

import kswiftk.internal.*

// MARK: - Predicate HOF scalar operations (runtime-backed)

fun String.count(predicate: (Char) -> Boolean): Int = __string_count_flat(this, predicate)

fun CharSequence.count(predicate: (Char) -> Boolean): Int = __string_count_flat(this, predicate)

fun String.any(predicate: (Char) -> Boolean): Boolean = __string_any_flat(this, predicate)

fun CharSequence.any(predicate: (Char) -> Boolean): Boolean = __string_any_flat(this, predicate)

fun String.all(predicate: (Char) -> Boolean): Boolean = __string_all_flat(this, predicate)

fun CharSequence.all(predicate: (Char) -> Boolean): Boolean = __string_all_flat(this, predicate)

fun String.none(predicate: (Char) -> Boolean): Boolean = __string_none_flat(this, predicate)

fun CharSequence.none(predicate: (Char) -> Boolean): Boolean = __string_none_flat(this, predicate)

fun String.indexOfFirst(predicate: (Char) -> Boolean): Int = __string_indexOfFirst_flat(this, predicate)

fun CharSequence.indexOfFirst(predicate: (Char) -> Boolean): Int = __string_indexOfFirst_flat(this, predicate)

fun String.indexOfLast(predicate: (Char) -> Boolean): Int = __string_indexOfLast_flat(this, predicate)

fun CharSequence.indexOfLast(predicate: (Char) -> Boolean): Int = __string_indexOfLast_flat(this, predicate)
