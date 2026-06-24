package kotlin.io.encoding

// MIGRATION-ENC-001
// Base64 encode/decode migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeBase64.swift (26 @_cdecl)
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// Sema stubs in HeaderHelpers+SyntheticBase64Stubs.swift and dispatch in
// CallLowerer+Base64MemberCalls.swift still route directly to kk_base64_* ABI.
// This file is the migration target; wiring (and removal of those stubs)
// happens in RF-STDLIB-004+.
//
// Implementation strategy:
//   - Base64.Default   — companion object (RFC 4648 §4, standard +/ alphabet)
//   - Base64.UrlSafe   — object (RFC 4648 §5, URL-safe -_ alphabet)
//   - Base64.Mime      — object (RFC 2045, +/ alphabet, CRLF every 76 chars)
//   - Base64.Pem       — object (alias for Mime variant)
//   - encode / decode / encodeToByteArray / decodeFromByteArray:
//       ABI bridge to kk_base64_{encode|decode}_{default|urlsafe|mime}
//   - withPadding: ABI bridge to kk_base64_withPadding_{default|urlsafe|mime}
//   - PaddingOption ordinals match Base64PaddingOption in RuntimeBase64.swift:
//       PRESENT=0, ABSENT=1, PRESENT_OPTIONAL=2, ABSENT_OPTIONAL=3
//   - String.decodingWith(codec) delegates to codec.decode(this)

// ─── ABI bridges — Default (RFC 4648 §4, +/ alphabet) ───────────────────────

private external fun kk_base64_encode_default(source: ByteArray, padding: Int): String
private external fun kk_base64_decode_default(source: String, padding: Int): ByteArray
private external fun kk_base64_encodeToByteArray_default(source: ByteArray, padding: Int): ByteArray
private external fun kk_base64_decodeFromByteArray_default(source: ByteArray, padding: Int): ByteArray
private external fun kk_base64_withPadding_default(paddingOptionRaw: Int): Base64

// ─── ABI bridges — UrlSafe (RFC 4648 §5, -_ alphabet) ──────────────────────

private external fun kk_base64_encode_urlsafe(source: ByteArray, padding: Int): String
private external fun kk_base64_decode_urlsafe(source: String, padding: Int): ByteArray
private external fun kk_base64_encodeToByteArray_urlsafe(source: ByteArray, padding: Int): ByteArray
private external fun kk_base64_decodeFromByteArray_urlsafe(source: ByteArray, padding: Int): ByteArray
private external fun kk_base64_withPadding_urlsafe(paddingOptionRaw: Int): Base64

// ─── ABI bridges — Mime (RFC 2045, +/ alphabet, CRLF every 76 chars) ────────

private external fun kk_base64_encode_mime(source: ByteArray, padding: Int): String
private external fun kk_base64_decode_mime(source: String, padding: Int): ByteArray
private external fun kk_base64_encodeToByteArray_mime(source: ByteArray, padding: Int): ByteArray
private external fun kk_base64_decodeFromByteArray_mime(source: ByteArray, padding: Int): ByteArray
private external fun kk_base64_withPadding_mime(paddingOptionRaw: Int): Base64

// ─── ABI bridges — instance dispatch ────────────────────────────────────────

private external fun kk_base64_encode_instance(instance: Base64, source: ByteArray): String
private external fun kk_base64_decode_instance(instance: Base64, source: String): ByteArray
private external fun kk_base64_encodeToByteArray_instance(instance: Base64, source: ByteArray): ByteArray
private external fun kk_base64_decodeFromByteArray_instance(instance: Base64, source: ByteArray): ByteArray
private external fun kk_base64_withPadding_instance(instance: Base64, paddingOptionRaw: Int): Base64

// ─── Base64 ──────────────────────────────────────────────────────────────────

public open class Base64 internal constructor() {

    public enum class PaddingOption {
        PRESENT,
        ABSENT,
        PRESENT_OPTIONAL,
        ABSENT_OPTIONAL,
    }

    public open fun encode(source: ByteArray): String =
        kk_base64_encode_instance(this, source)

    public open fun decode(source: String): ByteArray =
        kk_base64_decode_instance(this, source)

    public open fun encodeToByteArray(source: ByteArray): ByteArray =
        kk_base64_encodeToByteArray_instance(this, source)

    public open fun decodeFromByteArray(source: ByteArray): ByteArray =
        kk_base64_decodeFromByteArray_instance(this, source)

    public open fun withPadding(option: PaddingOption): Base64 =
        kk_base64_withPadding_instance(this, option.ordinal)

    public companion object Default : Base64() {
        override fun encode(source: ByteArray): String =
            kk_base64_encode_default(source, PaddingOption.PRESENT.ordinal)

        override fun decode(source: String): ByteArray =
            kk_base64_decode_default(source, PaddingOption.PRESENT.ordinal)

        override fun encodeToByteArray(source: ByteArray): ByteArray =
            kk_base64_encodeToByteArray_default(source, PaddingOption.PRESENT.ordinal)

        override fun decodeFromByteArray(source: ByteArray): ByteArray =
            kk_base64_decodeFromByteArray_default(source, PaddingOption.PRESENT.ordinal)

        override fun withPadding(option: PaddingOption): Base64 =
            kk_base64_withPadding_default(option.ordinal)
    }

    public object UrlSafe : Base64() {
        override fun encode(source: ByteArray): String =
            kk_base64_encode_urlsafe(source, PaddingOption.PRESENT.ordinal)

        override fun decode(source: String): ByteArray =
            kk_base64_decode_urlsafe(source, PaddingOption.PRESENT.ordinal)

        override fun encodeToByteArray(source: ByteArray): ByteArray =
            kk_base64_encodeToByteArray_urlsafe(source, PaddingOption.PRESENT.ordinal)

        override fun decodeFromByteArray(source: ByteArray): ByteArray =
            kk_base64_decodeFromByteArray_urlsafe(source, PaddingOption.PRESENT.ordinal)

        override fun withPadding(option: PaddingOption): Base64 =
            kk_base64_withPadding_urlsafe(option.ordinal)
    }

    public object Mime : Base64() {
        override fun encode(source: ByteArray): String =
            kk_base64_encode_mime(source, PaddingOption.PRESENT.ordinal)

        override fun decode(source: String): ByteArray =
            kk_base64_decode_mime(source, PaddingOption.PRESENT.ordinal)

        override fun encodeToByteArray(source: ByteArray): ByteArray =
            kk_base64_encodeToByteArray_mime(source, PaddingOption.PRESENT.ordinal)

        override fun decodeFromByteArray(source: ByteArray): ByteArray =
            kk_base64_decodeFromByteArray_mime(source, PaddingOption.PRESENT.ordinal)

        override fun withPadding(option: PaddingOption): Base64 =
            kk_base64_withPadding_mime(option.ordinal)
    }

    // Pem shares the Mime variant (same RFC 2045 alphabet and line wrapping).
    public object Pem : Base64() {
        override fun encode(source: ByteArray): String =
            kk_base64_encode_mime(source, PaddingOption.PRESENT.ordinal)

        override fun decode(source: String): ByteArray =
            kk_base64_decode_mime(source, PaddingOption.PRESENT.ordinal)

        override fun encodeToByteArray(source: ByteArray): ByteArray =
            kk_base64_encodeToByteArray_mime(source, PaddingOption.PRESENT.ordinal)

        override fun decodeFromByteArray(source: ByteArray): ByteArray =
            kk_base64_decodeFromByteArray_mime(source, PaddingOption.PRESENT.ordinal)

        override fun withPadding(option: PaddingOption): Base64 =
            kk_base64_withPadding_mime(option.ordinal)
    }
}

// ─── String.decodingWith (STDLIB-IO-ENC-FN-001) ─────────────────────────────

public fun String.decodingWith(codec: Base64): ByteArray = codec.decode(this)
