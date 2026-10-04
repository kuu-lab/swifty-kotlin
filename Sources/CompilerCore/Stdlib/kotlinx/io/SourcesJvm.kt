/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/jvm/src/SourcesJvm.kt (tag 0.9.1). Only `Source.asInputStream()`
 * is ported; upstream's `Source.readString`/`readAtMostTo(ByteBuffer)`/`asByteChannel` depend on
 * not-yet-ported APIs. The synthetic `java.io` stream stubs cannot be subclassed from Kotlin
 * source, so the adapter drains eagerly into a `ByteArrayInputStream` instead of returning
 * upstream's lazily-reading `InputStream` subclass.
 */
package kotlinx.io

import java.io.InputStream

/**
 * Returns an input stream that reads from this source.
 *
 * Unlike upstream, which returns an `InputStream` subclass that pulls from the
 * source lazily and forwards `close()` to it, this adapter drains the source
 * eagerly into a `ByteArrayInputStream`: reads are not performed lazily,
 * closing the stream does not close this source, and read failures surface at
 * adapt time instead of at `read()`.
 */
public fun Source.asInputStream(): InputStream {
    val buffer = Buffer()
    transferTo(buffer)
    val size = buffer.size
    if (size > Int.MAX_VALUE) {
        throw java.io.IOException("Source is too large to read into a ByteArrayInputStream")
    }
    val bytes = ByteArray(size.toInt())
    val copied = buffer.readAtMostTo(bytes, 0, size.toInt())
    if (copied < size.toInt()) {
        throw java.io.IOException("Source returned fewer bytes than expected")
    }
    return bytes.inputStream()
}
