package kotlin.collections

import java.util.stream.Stream

public fun <T> Collection<T>.stream(): Stream<T> = Stream.fromIterable(this)

public fun <T> Collection<T>.parallelStream(): Stream<T> = Stream.fromIterable(this).parallel()
