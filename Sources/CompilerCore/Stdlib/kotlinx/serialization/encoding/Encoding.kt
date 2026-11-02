/*
 * Copyright 2017-2024 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization.encoding

import kotlinx.serialization.modules.SerializersModule

/** Minimal format-specific sink surface currently exposed by the bundled stdlib. */
public interface Encoder {
    public val serializersModule: SerializersModule

    public fun encodeString(value: String)

    public fun encodeNotNullMark() {}

    public fun encodeNull()
}

/** Minimal format-specific source surface currently exposed by the bundled stdlib. */
public interface Decoder {
    public val serializersModule: SerializersModule

    public fun decodeString(): String

    public fun decodeNotNullMark(): Boolean

    public fun decodeNull(): Nothing?
}
