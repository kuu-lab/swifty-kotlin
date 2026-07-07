package kotlin.sequences

import kotlin.collections.IndexedValue
import kotlin.internal.KsSymbolName

// MIGRATION-SEQ-006 / KSP-441
// Runtime-backed sequence transform surface.
//
// The source-backed lazy object pipelines currently require callable object
// literal properties to be invoked from member functions. Keep the bundled
// declarations wired to the existing runtime ABI until that lowering path is
// ready, so stdlib compilation remains clean while the public surface stays
// source-owned.

@KsSymbolName("kk_sequence_map")
public external fun <T, R> Sequence<T>.map(transform: (T) -> R): Sequence<R>

@KsSymbolName("kk_sequence_mapIndexed")
public external fun <T, R> Sequence<T>.mapIndexed(transform: (index: Int, T) -> R): Sequence<R>

@KsSymbolName("kk_sequence_mapNotNull")
public external fun <T, R : Any> Sequence<T>.mapNotNull(transform: (T) -> R?): Sequence<R>

@KsSymbolName("kk_sequence_mapIndexedNotNull")
public external fun <T, R : Any> Sequence<T>.mapIndexedNotNull(transform: (index: Int, T) -> R?): Sequence<R>

@KsSymbolName("kk_sequence_filter")
public external fun <T> Sequence<T>.filter(predicate: (T) -> Boolean): Sequence<T>

@KsSymbolName("kk_sequence_filterNot")
public external fun <T> Sequence<T>.filterNot(predicate: (T) -> Boolean): Sequence<T>

@KsSymbolName("kk_sequence_filterIndexed")
public external fun <T> Sequence<T>.filterIndexed(predicate: (index: Int, T) -> Boolean): Sequence<T>

@KsSymbolName("kk_sequence_filterNotNull")
public external fun <T : Any> Sequence<T?>.filterNotNull(): Sequence<T>

@KsSymbolName("kk_sequence_filterIsInstance")
public inline external fun <reified R> Sequence<*>.filterIsInstance(): Sequence<R>

@KsSymbolName("kk_sequence_requireNoNulls")
public external fun <T : Any> Sequence<T?>.requireNoNulls(): Sequence<T>

@KsSymbolName("kk_sequence_flatMap")
public external fun <T, R> Sequence<T>.flatMap(transform: (T) -> Iterable<R>): Sequence<R>

@KsSymbolName("kk_sequence_flatMap")
public external fun <T, R> Sequence<T>.flatMap(transform: (T) -> Sequence<R>): Sequence<R>

@KsSymbolName("kk_sequence_flatMapIndexed")
public external fun <T, R> Sequence<T>.flatMapIndexed(transform: (index: Int, T) -> Iterable<R>): Sequence<R>

@KsSymbolName("kk_sequence_flatMapIndexed")
public external fun <T, R> Sequence<T>.flatMapIndexed(transform: (index: Int, T) -> Sequence<R>): Sequence<R>

@KsSymbolName("kk_sequence_onEach")
public external fun <T> Sequence<T>.onEach(action: (T) -> Unit): Sequence<T>

@KsSymbolName("kk_sequence_onEachIndexed")
public external fun <T> Sequence<T>.onEachIndexed(action: (index: Int, T) -> Unit): Sequence<T>

@KsSymbolName("kk_sequence_withIndex")
public external fun <T> Sequence<T>.withIndex(): Sequence<IndexedValue<T>>
