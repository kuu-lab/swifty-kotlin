@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

import kotlin.sequences.chunked
import kotlin.sequences.windowed
import kotlin.sequences.sortedBy
import kotlin.sequences.sortedByDescending
import kotlin.sequences.toList

fun <T> Iterable<T>.chunked(size: Int): List<List<T>> = this.asSequence().chunked(size).toList()
fun <T, R> Iterable<T>.chunked(size: Int, transform: (List<T>) -> R): List<R> = this.asSequence().chunked(size, transform).toList()
fun <T> Iterable<T>.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<T>> = this.asSequence().windowed(size, step, partialWindows).toList()
fun <T, R: Comparable<R>> Iterable<T>.sortedBy(selector: (T) -> R?): List<T> = this.asSequence().sortedBy(selector).toList()
fun <T, R: Comparable<R>> Iterable<T>.sortedByDescending(selector: (T) -> R?): List<T> = this.asSequence().sortedByDescending(selector).toList()
