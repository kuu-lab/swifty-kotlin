package kotlin.sequences

import kotlin.collections.IndexedValue

// MIGRATION-SEQ-006 / KSP-441
// Runtime-backed sequence transform surface.
//
// The source-backed lazy object pipelines currently require callable object
// literal properties to be invoked from member functions. Keep the bundled
// declarations wired to the existing runtime ABI until that lowering path is
// ready, so stdlib compilation remains clean while the public surface stays
// source-owned.

public external fun <T, R> Sequence<T>.map(transform: (T) -> R): Sequence<R>

public external fun <T, R> Sequence<T>.mapIndexed(transform: (index: Int, T) -> R): Sequence<R>

public external fun <T, R : Any> Sequence<T>.mapNotNull(transform: (T) -> R?): Sequence<R>

public external fun <T, R : Any> Sequence<T>.mapIndexedNotNull(transform: (index: Int, T) -> R?): Sequence<R>

public external fun <T> Sequence<T>.filter(predicate: (T) -> Boolean): Sequence<T>

public external fun <T> Sequence<T>.filterNot(predicate: (T) -> Boolean): Sequence<T>

public external fun <T> Sequence<T>.filterIndexed(predicate: (index: Int, T) -> Boolean): Sequence<T>

public external fun <T : Any> Sequence<T?>.filterNotNull(): Sequence<T>

public inline external fun <reified R> Sequence<*>.filterIsInstance(): Sequence<R>

public external fun <T : Any> Sequence<T?>.requireNoNulls(): Sequence<T>

public external fun <T, R> Sequence<T>.flatMap(transform: (T) -> Iterable<R>): Sequence<R>

public external fun <T, R> Sequence<T>.flatMap(transform: (T) -> Sequence<R>): Sequence<R>

public external fun <T, R> Sequence<T>.flatMapIndexed(transform: (index: Int, T) -> Iterable<R>): Sequence<R>

public external fun <T, R> Sequence<T>.flatMapIndexed(transform: (index: Int, T) -> Sequence<R>): Sequence<R>

public external fun <T> Sequence<T>.onEach(action: (T) -> Unit): Sequence<T>

public external fun <T> Sequence<T>.onEachIndexed(action: (index: Int, T) -> Unit): Sequence<T>

public external fun <T> Sequence<T>.withIndex(): Sequence<IndexedValue<T>>
