@file:kotlin.jvm.JvmName("StringsKt")
package kotlin.text
inline fun <R> CharSequence.map(transform: (Char) -> R): List<R> { val result = mutableListOf<R>(); for (c in this) result.add(transform(c)); return result }
inline fun <R> CharSequence.mapIndexed(transform: (Int, Char) -> R): List<R> { val result = mutableListOf<R>(); var i = 0; for (c in this) { result.add(transform(i, c)); i++ }; return result }
inline fun <R: Any> CharSequence.mapNotNull(transform: (Char) -> R?): List<R> { val result = mutableListOf<R>(); for (c in this) { val item = transform(c); if (item != null) result.add(item) }; return result }
inline fun <R: Any> CharSequence.mapIndexedNotNull(transform: (Int, Char) -> R?): List<R> { val result = mutableListOf<R>(); var i = 0; for (c in this) { val item = transform(i, c); if (item != null) result.add(item); i++ }; return result }
inline fun <R> CharSequence.flatMap(transform: (Char) -> Iterable<R>): List<R> { val result = mutableListOf<R>(); var i = 0; for (c in this) { for (item in transform(c)) result.add(item); i++ }; return result }
inline fun <R> CharSequence.flatMapIndexed(transform: (Int, Char) -> Iterable<R>): List<R> { val result = mutableListOf<R>(); var i = 0; for (c in this) { for (item in transform(i, c)) result.add(item); i++ }; return result }
inline fun String.filter(predicate: (Char) -> Boolean): String { val result = StringBuilder(); val size = this.length; var i = 0; while (i < size) { val c = this[i]; if (predicate(c)) result.append(c); i++ }; return result.toString() }
inline fun String.filterNot(predicate: (Char) -> Boolean): String { val result = StringBuilder(); var i = 0; for (c in this) { if (!predicate(c)) result.append(c); i++ }; return result.toString() }
inline fun String.filterIndexed(predicate: (Int, Char) -> Boolean): String { val result = StringBuilder(); var i = 0; for (c in this) { if (predicate(i, c)) result.append(c); i++ }; return result.toString() }
inline fun String.takeWhile(predicate: (Char) -> Boolean): String { val size = this.length; var i = 0; while (i < size) { if (!predicate(this[i])) return this.substring(0, i); i++ }; return this }
inline fun String.dropWhile(predicate: (Char) -> Boolean): String { val size = this.length; var i = 0; while (i < size) { if (!predicate(this[i])) return this.substring(i, this.length); i++ }; return "" }
inline fun String.takeLastWhile(predicate: (Char) -> Boolean): String { var i = this.length - 1; while (i >= 0) { if (!predicate(this[i])) return this.substring(i + 1, this.length); i-- }; return this }
inline fun String.dropLastWhile(predicate: (Char) -> Boolean): String { var i = this.length - 1; while (i >= 0) { if (!predicate(this[i])) return this.substring(0, i + 1); i-- }; return "" }
inline fun CharSequence.filter(predicate: (Char) -> Boolean): CharSequence { val result = StringBuilder(); val size = this.length; var i = 0; while (i < size) { val c = this[i]; if (predicate(c)) result.append(c); i++ }; return result }
inline fun CharSequence.filterNot(predicate: (Char) -> Boolean): CharSequence { val result = StringBuilder(); var i = 0; for (c in this) { if (!predicate(c)) result.append(c); i++ }; return result }
inline fun CharSequence.filterIndexed(predicate: (Int, Char) -> Boolean): CharSequence { val result = StringBuilder(); var i = 0; for (c in this) { if (predicate(i, c)) result.append(c); i++ }; return result }
inline fun CharSequence.takeWhile(predicate: (Char) -> Boolean): CharSequence { val size = this.length; var i = 0; while (i < size) { if (!predicate(this[i])) return this.subSequence(0, i); i++ }; return this.subSequence(0, this.length) }
inline fun CharSequence.dropWhile(predicate: (Char) -> Boolean): CharSequence { val size = this.length; var i = 0; while (i < size) { if (!predicate(this[i])) return this.subSequence(i, this.length); i++ }; return "" }
inline fun CharSequence.takeLastWhile(predicate: (Char) -> Boolean): CharSequence { var i = this.length - 1; while (i >= 0) { if (!predicate(this[i])) return this.subSequence(i + 1, this.length); i-- }; return this.subSequence(0, this.length) }
inline fun CharSequence.dropLastWhile(predicate: (Char) -> Boolean): CharSequence { var i = this.length - 1; while (i >= 0) { if (!predicate(this[i])) return this.subSequence(0, i + 1); i-- }; return "" }
inline fun CharSequence.forEach(action: (Char) -> Unit): Unit { for (c in this) action(c) }
inline fun CharSequence.forEachIndexed(action: (Int, Char) -> Unit): Unit { var i = 0; for (c in this) { action(i, c); i++ } }
inline fun <S: CharSequence> S.onEach(action: (Char) -> Unit): S { for (c in this) action(c); return this }
inline fun <S: CharSequence> S.onEachIndexed(action: (Int, Char) -> Unit): S { var i = 0; for (c in this) { action(i, c); i++ }; return this }
inline fun CharSequence.any(predicate: (Char) -> Boolean): Boolean { for (c in this) if (predicate(c)) return true; return false }
inline fun CharSequence.all(predicate: (Char) -> Boolean): Boolean { for (c in this) if (!predicate(c)) return false; return true }
inline fun CharSequence.none(predicate: (Char) -> Boolean): Boolean { for (c in this) if (predicate(c)) return false; return true }
inline fun CharSequence.count(predicate: (Char) -> Boolean): Int { var count = 0; for (c in this) if (predicate(c)) count++; return count }
inline fun <R> CharSequence.fold(initial: R, operation: (R, Char) -> R): R { var accumulator = initial; var i = 0; for (c in this) { accumulator = operation(accumulator, c); i++ }; return accumulator }
inline fun <R> CharSequence.foldIndexed(initial: R, operation: (Int, R, Char) -> R): R { var accumulator = initial; var i = 0; for (c in this) { accumulator = operation(i, accumulator, c); i++ }; return accumulator }
inline fun <R> CharSequence.foldRight(initial: R, operation: (Char, R) -> R): R { var accumulator = initial; var i = this.length - 1; while (i >= 0) { accumulator = operation(this[i], accumulator); i-- }; return accumulator }
inline fun <R> CharSequence.foldRightIndexed(initial: R, operation: (Int, Char, R) -> R): R { var accumulator = initial; var i = this.length - 1; while (i >= 0) { accumulator = operation(i, this[i], accumulator); i-- }; return accumulator }
inline fun CharSequence.first(predicate: (Char) -> Boolean): Char { for (c in this) if (predicate(c)) return c; throw NoSuchElementException("Char sequence contains no character matching the predicate.") }
inline fun CharSequence.firstOrNull(predicate: (Char) -> Boolean): Char? { for (c in this) if (predicate(c)) return c; return null }
inline fun CharSequence.find(predicate: (Char) -> Boolean): Char? { for (c in this) if (predicate(c)) return c; return null }
inline fun CharSequence.last(predicate: (Char) -> Boolean): Char { var i = this.length - 1; while (i >= 0) { val c = this[i]; if (predicate(c)) return c; i-- }; throw NoSuchElementException("Char sequence contains no character matching the predicate.") }
inline fun CharSequence.lastOrNull(predicate: (Char) -> Boolean): Char? { var i = this.length - 1; while (i >= 0) { val c = this[i]; if (predicate(c)) return c; i-- }; return null }
inline fun CharSequence.findLast(predicate: (Char) -> Boolean): Char? { var i = this.length - 1; while (i >= 0) { val c = this[i]; if (predicate(c)) return c; i-- }; return null }
inline fun CharSequence.indexOfFirst(predicate: (Char) -> Boolean): Int { val size = this.length; var i = 0; while (i < size) { if (predicate(this[i])) return i; i++ }; return -1 }
inline fun CharSequence.indexOfLast(predicate: (Char) -> Boolean): Int { var i = this.length - 1; while (i >= 0) { if (predicate(this[i])) return i; i-- }; return -1 }
inline fun CharSequence.reduce(operation: (Char, Char) -> Char): Char { if (this.length == 0) { throw UnsupportedOperationException("Empty char sequence can't be reduced.") }; val size = this.length; var accumulator = this[0]; var i = 1; while (i < size) { accumulator = operation(accumulator, this[i]); i++ }; return accumulator }
inline fun CharSequence.reduceOrNull(operation: (Char, Char) -> Char): Char? { if (this.length == 0) { return null }; val size = this.length; var accumulator = this[0]; var i = 1; while (i < size) { accumulator = operation(accumulator, this[i]); i++ }; return accumulator }
inline fun CharSequence.reduceIndexed(operation: (Int, Char, Char) -> Char): Char { if (this.length == 0) { throw UnsupportedOperationException("Empty char sequence can't be reduced.") }; val size = this.length; var accumulator = this[0]; var i = 1; while (i < size) { accumulator = operation(i, accumulator, this[i]); i++ }; return accumulator }
inline fun CharSequence.reduceIndexedOrNull(operation: (Int, Char, Char) -> Char): Char? { if (this.length == 0) { return null }; val size = this.length; var accumulator = this[0]; var i = 1; while (i < size) { accumulator = operation(i, accumulator, this[i]); i++ }; return accumulator }
inline fun CharSequence.reduceRight(operation: (Char, Char) -> Char): Char { if (this.length == 0) { throw UnsupportedOperationException("Empty char sequence can't be reduced.") }; val size = this.length; var accumulator = this[size - 1]; var i = size - 2; while (i >= 0) { accumulator = operation(this[i], accumulator); i-- }; return accumulator }
inline fun CharSequence.reduceRightOrNull(operation: (Char, Char) -> Char): Char? { if (this.length == 0) { return null }; val size = this.length; var accumulator = this[size - 1]; var i = size - 2; while (i >= 0) { accumulator = operation(this[i], accumulator); i-- }; return accumulator }
inline fun CharSequence.reduceRightIndexed(operation: (Int, Char, Char) -> Char): Char { if (this.length == 0) { throw UnsupportedOperationException("Empty char sequence can't be reduced.") }; val size = this.length; var accumulator = this[size - 1]; var i = size - 2; while (i >= 0) { accumulator = operation(i, this[i], accumulator); i-- }; return accumulator }
inline fun CharSequence.reduceRightIndexedOrNull(operation: (Int, Char, Char) -> Char): Char? { if (this.length == 0) { return null }; val size = this.length; var accumulator = this[size - 1]; var i = size - 2; while (i >= 0) { accumulator = operation(i, this[i], accumulator); i-- }; return accumulator }
inline fun CharSequence.single(predicate: (Char) -> Boolean): Char { var found = false; var result = ' '; for (c in this) { if (predicate(c)) { if (found) { throw IllegalArgumentException("Char sequence contains more than one matching element.") }; found = true; result = c } }; if (!found) { throw NoSuchElementException("Char sequence contains no character matching the predicate.") }; return result }
inline fun CharSequence.singleOrNull(predicate: (Char) -> Boolean): Char? { var found = false; var result = ' '; for (c in this) { if (predicate(c)) { if (found) { return null }; found = true; result = c } }; if (!found) { return null }; return result }
inline fun CharSequence.any(): Boolean { return this.length != 0 }
inline fun CharSequence.none(): Boolean { return this.length == 0 }
inline fun CharSequence.count(): Int { return this.length }
inline fun CharSequence.toList(): List<Char> { val result = mutableListOf<Char>(); for (c in this) result.add(c); return result }
inline fun CharSequence.toSet(): Set<Char> { val result = mutableSetOf<Char>(); for (c in this) result.add(c); return result }
inline fun <R> CharSequence.zipWithNext(transform: (Char, Char) -> R): List<R> { val result = mutableListOf<R>(); val size = this.length; var i = 1; while (i < size) { result.add(transform(this[i - 1], this[i])); i++ }; return result }
inline fun buildString(builderAction: StringBuilder.() -> Unit): String { val builder = StringBuilder(); builder.builderAction(); return builder.toString() }
inline fun buildString(capacity: Int, builderAction: StringBuilder.() -> Unit): String { val builder = StringBuilder(capacity); builder.builderAction(); return builder.toString() }
