/*
 * Copyright 2017-2024 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/encoding/ChunkedDecoder.kt.
 */

package kotlinx.serialization.encoding

import kotlinx.serialization.ExperimentalSerializationApi

@ExperimentalSerializationApi
public interface ChunkedDecoder {
    @ExperimentalSerializationApi
    public fun decodeStringChunked(consumeChunk: (chunk: String) -> Unit)
}
