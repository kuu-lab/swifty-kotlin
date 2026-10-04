package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-717: KSwiftK extension, not part of upstream kotlin-stdlib (JVM exposes
// java.text.Normalizer instead; Kotlin/Native has no normalize API at all).
// Unicode normalization itself stays a runtime bridge (ICU/Foundation); only
// the form tag crosses the ABI boundary as a plain Int.

public class NormalizationForm internal constructor(internal val tag: Int)

public object NormalizationForms {
    public val NFC: NormalizationForm = NormalizationForm(0)
    public val NFD: NormalizationForm = NormalizationForm(1)
    public val NFKC: NormalizationForm = NormalizationForm(2)
    public val NFKD: NormalizationForm = NormalizationForm(3)
}

@KsSymbolName("__kk_string_normalize_flat")
internal external fun String.__kk_string_normalize_flat(formTag: Int): String

@KsSymbolName("__kk_string_isNormalized_flat")
internal external fun String.__kk_string_isNormalized_flat(formTag: Int): Boolean

public fun String.normalize(form: NormalizationForm): String =
    this.__kk_string_normalize_flat(form.tag)

public fun String.isNormalized(form: NormalizationForm): Boolean =
    this.__kk_string_isNormalized_flat(form.tag)
