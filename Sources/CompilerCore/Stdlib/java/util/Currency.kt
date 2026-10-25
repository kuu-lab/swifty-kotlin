package java.util

public class Currency private constructor(
    public val currencyCode: String,
    public val defaultFractionDigits: Int,
) {
    public fun getSymbol(): String = currencyCode

    public fun getSymbol(locale: Locale): String = currencyCode

    public fun getDisplayName(): String = currencyCode

    public fun getDisplayName(locale: Locale): String = currencyCode

    public companion object {
        private val instances = HashMap<String, Currency>()

        public fun getInstance(currencyCode: String): Currency {
            if (!isCurrencyCode(currencyCode)) {
                throw IllegalArgumentException("Invalid currency code: $currencyCode")
            }
            val existing = instances[currencyCode]
            if (existing != null) return existing

            val currency = Currency(currencyCode, fractionDigits(currencyCode))
            instances[currencyCode] = currency
            return currency
        }

        public fun getInstance(locale: Locale): Currency {
            val code = currencyCodeForCountry(locale.country)
                ?: throw IllegalArgumentException("No currency for locale: $locale")
            return getInstance(code)
        }

        private fun isCurrencyCode(code: String): Boolean {
            if (code.length != 3) return false
            for (character in code) {
                if (character < 'A' || character > 'Z') return false
            }
            return true
        }

        private fun fractionDigits(code: String): Int = when (code) {
            "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND" -> 3
            "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
            "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF" -> 0
            "XXX" -> -1
            else -> 2
        }

        private fun currencyCodeForCountry(country: String): String? = when (country) {
            "US" -> "USD"
            "CA" -> "CAD"
            "GB" -> "GBP"
            "JP" -> "JPY"
            "CN" -> "CNY"
            "IN" -> "INR"
            "AU" -> "AUD"
            "CH" -> "CHF"
            "KR" -> "KRW"
            "DE", "FR", "IT", "ES", "NL", "BE", "PT", "IE", "AT", "FI", "GR" -> "EUR"
            else -> null
        }
    }
}
