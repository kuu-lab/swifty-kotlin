@file:OptIn(kotlin.io.encoding.ExperimentalEncodingApi::class)

package java.util

/** Java-compatible facade over the bundled Kotlin Base64 codecs. */
public class Base64 private constructor() {
    public class Encoder internal constructor(
        private val codec: kotlin.io.encoding.Base64
    ) {
        public fun encode(source: ByteArray): ByteArray = codec.encodeToByteArray(source)

        public fun encodeToString(source: ByteArray): String = codec.encode(source)

        public fun withoutPadding(): Encoder =
            Encoder(codec.withPadding(kotlin.io.encoding.Base64.PaddingOption.ABSENT))
    }

    public class Decoder internal constructor(
        private val codec: kotlin.io.encoding.Base64
    ) {
        public fun decode(source: ByteArray): ByteArray = codec.decode(source)

        public fun decode(source: String): ByteArray = codec.decode(source)
    }

    public companion object {
        public fun getEncoder(): Encoder = Encoder(kotlin.io.encoding.Base64.Default)

        public fun getUrlEncoder(): Encoder = Encoder(kotlin.io.encoding.Base64.UrlSafe)

        public fun getMimeEncoder(): Encoder = Encoder(kotlin.io.encoding.Base64.Mime)

        public fun getDecoder(): Decoder = Decoder(decoderCodec(kotlin.io.encoding.Base64.Default))

        public fun getUrlDecoder(): Decoder = Decoder(decoderCodec(kotlin.io.encoding.Base64.UrlSafe))

        public fun getMimeDecoder(): Decoder = Decoder(decoderCodec(kotlin.io.encoding.Base64.Mime))

        private fun decoderCodec(codec: kotlin.io.encoding.Base64): kotlin.io.encoding.Base64 =
            codec.withPadding(kotlin.io.encoding.Base64.PaddingOption.ABSENT_OPTIONAL)
    }
}
