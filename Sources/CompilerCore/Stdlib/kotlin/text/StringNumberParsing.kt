package kotlin.text

import kotlin.internal.KsSymbolName
import java.math.BigDecimal

@KsSymbolName("__kk_string_toFloat")
private external fun __kk_string_toFloat(str: String): Float

@KsSymbolName("__kk_string_toFloatOrNull")
private external fun __kk_string_toFloatOrNull(str: String): Float?

@KsSymbolName("__kk_string_toDouble")
private external fun __kk_string_toDouble(str: String): Double

@KsSymbolName("__kk_string_toDoubleOrNull")
private external fun __kk_string_toDoubleOrNull(str: String): Double?

@KsSymbolName("__kk_string_toBigDecimal")
private external fun __kk_string_toBigDecimal(str: String): BigDecimal

@KsSymbolName("__kk_string_toBigDecimalOrNull")
private external fun __kk_string_toBigDecimalOrNull(str: String): BigDecimal?

public fun String.toFloat(): Float {
    return __kk_string_toFloat(this)
}

public fun String.toFloatOrNull(): Float? {
    return __kk_string_toFloatOrNull(this)
}

public fun String.toDouble(): Double {
    return __kk_string_toDouble(this)
}

public fun String.toDoubleOrNull(): Double? {
    return __kk_string_toDoubleOrNull(this)
}

public fun String.toBigDecimal(): BigDecimal {
    return __kk_string_toBigDecimal(this)
}

public fun String.toBigDecimalOrNull(): BigDecimal? {
    return __kk_string_toBigDecimalOrNull(this)
}
