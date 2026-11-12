package kotlin.io.encoding

import kotlin.enums.enumEntries
import kotlin.internal.KsSymbolName

public val Base64.PaddingOption.entries: kotlin.enums.EnumEntries<Base64.PaddingOption>
    get() = enumEntries<Base64.PaddingOption>()

// The runtime bridge wraps a stateful native OutputStream sink.
@KsSymbolName("__kk_output_stream_encodingWith")
private external fun __outputStreamEncodingWith(
    stream: java.io.OutputStream,
    alphabet: String,
    addPadding: Boolean
): java.io.OutputStream

public fun java.io.OutputStream.encodingWith(base64: Base64): java.io.OutputStream =
    __outputStreamEncodingWith(
        this,
        base64.alphabetChars,
        base64.paddingOption == Base64.PaddingOption.PRESENT || base64.paddingOption == Base64.PaddingOption.PRESENT_OPTIONAL
    )
