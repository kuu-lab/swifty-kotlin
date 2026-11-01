/*
 * Copyright 2017-2024 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/encoding/ChunkedDecoder.kt.
 */

package kotlinx.serialization.encoding

import kotlinx.serialization.ExperimentalSerializationApi

/**
 * This interface indicates that decoder supports consuming large strings by chunks via consumeChunk method.
 * Currently, only streaming json decoder implements this interface.
 * Please note that this interface is only applicable to streaming decoders. That means that it is not possible to use
 * some JsonTreeDecoder features like polymorphism with this interface.
 */
@ExperimentalSerializationApi
public interface ChunkedDecoder {
    /**
     * Method allows decoding a string value by fixed-size chunks.
     * Usable for handling very large strings that may not fit in memory.
     * Chunk size is guaranteed to not exceed 16384 chars (but it may be smaller than that).
     * Feeds string chunks to the provided consumer.
     */
    @ExperimentalSerializationApi
    public fun decodeStringChunked(consumeChunk: (chunk: String) -> Unit)
}
