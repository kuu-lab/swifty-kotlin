package java.io

import kotlin.internal.KsSymbolName

// KUU-3449: `java.io.Closeable { }` SAM factory for the JVM-compat anchor
// (a synthetic `java.io.Closeable` interface that extends
// `kotlin.io.Closeable`). Shares the `__kk_closeable_create` bridge with
// the `kotlin.io.Closeable` factory; the returned box answers `close()`
// dispatched through either Closeable nominal.
@KsSymbolName("__kk_closeable_create")
public external fun Closeable(closeAction: () -> Unit): Closeable
