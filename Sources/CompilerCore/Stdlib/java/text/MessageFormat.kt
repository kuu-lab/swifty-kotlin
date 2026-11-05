package java.text

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.util.Date
import java.util.Locale
import kotlin.internal.KsSymbolName

/**
 * `java.text.MessageFormat` — argument-substitution formatter.
 *
 * Supported surface (sufficient for Rosetta Calendar and typical
 * `MessageFormat.format` call sites):
 *  - `{n}` plain substitution. Numbers use the locale default number format
 *    (`#,##0.###` equivalent), `java.util.Date` uses SHORT date+time, other
 *    objects use `toString()`, `null` renders as `null`.
 *  - `{n,number[,style]}` with `integer`, `percent`, `currency`, and custom
 *    `DecimalFormat`-style patterns (`0`, `#`, `,`, `.`, `E`, `%`, `;`,
 *    quoted literals).
 *  - `{n,date[,style]}` / `{n,time[,style]}` with `short`/`medium`/`long`/`full`
 *    styles or a custom `SimpleDateFormat` pattern. `Date` and `Number`
 *    (epoch millis) arguments are accepted.
 *  - `{n,choice,limit#msg|...}` numeric limits with lower-bound-inclusive
 *    intervals and recursive sub-pattern messages.
 *  - Apostrophe quoting (`''` -> `'`, `'...'` literals) and literal echo of
 *    out-of-range arguments (`{n}` text preserved).
 *
 * Deferred / approximations: `ArgumentIndex` recursion via `{n,m}` is not
 * supported (JDK-specific nested argument indexes are rare); `<` interval
 * syntax in choice limits is rejected; RTL mark details for `ar` currency are
 * approximated; locales outside the bundled tables fall back to en-US style.
 */
public class MessageFormat {
    private var pattern: String = ""
    private var locale: Locale = Locale.getDefault()
    private var elements: List<FormatElement> = emptyList()

    private val DEFAULT_NUMBER_PATTERN: NumberPattern = parseNumberPattern("#,##0.###")
    private val INTEGER_NUMBER_PATTERN: NumberPattern = parseNumberPattern("#,##0")

    public constructor(pattern: String) : this(pattern, Locale.getDefault())

    public constructor(pattern: String, locale: Locale) {
        this.locale = locale
        applyPattern(pattern)
    }

    /** (Re)parses the pattern; invalid syntax throws `IllegalArgumentException` like the JDK. */
    public fun applyPattern(pattern: String) {
        this.pattern = pattern
        this.elements = parsePattern(pattern)
    }

    public fun toPattern(): String = pattern

    public fun setLocale(locale: Locale) {
        this.locale = locale
    }

    public fun getLocale(): Locale = locale

    public fun format(vararg arguments: Any?): String = formatArgumentList(arguments.toList())

    public fun format(arguments: Array<out Any?>): String = formatArgumentList(arguments.toList())

    private fun formatArgumentList(arguments: List<Any?>): String {
        return renderElements(elements, arguments, locale)
    }

    private fun renderElements(
        elementList: List<FormatElement>,
        arguments: List<Any?>,
        effectiveLocale: Locale,
    ): String {
        val out = StringBuilder()
        for (element in elementList) {
            if (!element.isArgument) {
                out.append(element.literal)
                continue
            }
            if (element.argIndex >= arguments.size) {
                // JDK echoes the original "{...}" text for missing arguments.
                out.append(element.rawText)
                continue
            }
            val arg = arguments[element.argIndex]
            when (element.formatType) {
                null -> appendPlainArgument(arg, effectiveLocale, out)
                FORMAT_NUMBER -> appendNumberArgument(arg, element, effectiveLocale, out)
                FORMAT_DATE -> appendDateArgument(arg, element, false, effectiveLocale, out)
                FORMAT_TIME -> appendDateArgument(arg, element, true, effectiveLocale, out)
                FORMAT_CHOICE -> appendChoiceArgument(arg, element, arguments, effectiveLocale, out)
                else -> out.append(arg?.toString() ?: "null")
            }
        }
        return out.toString()
    }

    private fun appendPlainArgument(arg: Any?, locale: Locale, out: StringBuilder) {
        when (arg) {
            null -> out.append("null")
            is Number -> {
                if (isNonFinite(arg)) {
                    out.append(nonFiniteText(arg))
                } else {
                    out.append(formatNumberValue(numberToBigDecimal(arg), DEFAULT_NUMBER_PATTERN, numberLocaleFor(locale)))
                }
            }
            is Date -> out.append(
                __messageFormatDateTime(DATETIME_KIND_BOTH, DATETIME_STYLE_SHORT, arg.time, locale)
            )
            else -> out.append(arg.toString())
        }
    }

    private fun appendNumberArgument(arg: Any?, element: FormatElement, locale: Locale, out: StringBuilder) {
        if (arg == null) {
            out.append("null")
            return
        }
        if (arg !is Number) {
            throw IllegalArgumentException("Cannot format given Object as a Number")
        }
        if (isNonFinite(arg)) {
            out.append(nonFiniteText(arg))
            return
        }
        val info = numberLocaleFor(locale)
        when (element.numberStyleKind) {
            NumberStyleKind.INTEGER -> out.append(
                formatNumberValue(numberToBigDecimal(arg), INTEGER_NUMBER_PATTERN, info)
            )
            NumberStyleKind.PERCENT -> {
                val scaled = numberToBigDecimal(arg).multiply(BigDecimal("100"))
                val core = formatNumberValue(scaled, INTEGER_NUMBER_PATTERN, info)
                out.append(info.percentPrefix).append(core).append(info.percentSuffix)
            }
            NumberStyleKind.CURRENCY -> {
                val currencyPattern = parseNumberPattern(info.currencyPattern)
                out.append(formatNumberValue(numberToBigDecimal(arg), currencyPattern, info))
            }
            NumberStyleKind.CUSTOM -> {
                // Parsed eagerly in applyPattern; re-resolve defensively.
                val pattern = element.numberPattern
                    ?: parseNumberPattern(element.formatStyle ?: DEFAULT_NUMBER_STYLE)
                out.append(formatNumberValue(numberToBigDecimal(arg), pattern, info))
            }
            NumberStyleKind.NONE -> out.append(
                formatNumberValue(numberToBigDecimal(arg), DEFAULT_NUMBER_PATTERN, info)
            )
            NumberStyleKind.DEFAULT -> out.append(
                formatNumberValue(numberToBigDecimal(arg), DEFAULT_NUMBER_PATTERN, info)
            )
            else -> out.append(
                formatNumberValue(numberToBigDecimal(arg), DEFAULT_NUMBER_PATTERN, info)
            )
        }
    }

    private fun appendDateArgument(
        arg: Any?,
        element: FormatElement,
        isTime: Boolean,
        locale: Locale,
        out: StringBuilder,
    ) {
        if (arg == null) {
            out.append("null")
            return
        }
        val millis: Long = when (arg) {
            is Date -> arg.time
            is Number -> arg.toLong()
            else -> throw IllegalArgumentException("Cannot format given Object as a Date")
        }
        val style = element.formatStyle
        if (style == null || style.isEmpty()) {
            // JDK default for {n,date}/{n,time} is the medium style.
            out.append(__messageFormatDateTime(if (isTime) DATETIME_KIND_TIME else DATETIME_KIND_DATE, DATETIME_STYLE_MEDIUM, millis, locale))
            return
        }
        val styleIndex = when (style.lowercase()) {
            "short" -> DATETIME_STYLE_SHORT
            "medium" -> DATETIME_STYLE_MEDIUM
            "long" -> DATETIME_STYLE_LONG
            "full" -> DATETIME_STYLE_FULL
            else -> -1
        }
        if (styleIndex >= 0) {
            out.append(
                __messageFormatDateTime(if (isTime) DATETIME_KIND_TIME else DATETIME_KIND_DATE, styleIndex, millis, locale)
            )
        } else {
            // Custom SimpleDateFormat pattern.
            out.append(__simpleDateFormatFormat(style, millis, locale))
        }
    }

    private fun appendChoiceArgument(
        arg: Any?,
        element: FormatElement,
        arguments: List<Any?>,
        locale: Locale,
        out: StringBuilder,
    ) {
        if (arg == null) {
            out.append("null")
            return
        }
        if (arg !is Number || isNonFinite(arg)) {
            throw IllegalArgumentException("Cannot format given Object as a Number")
        }
        val options = element.choiceOptions
            ?: parseChoiceOptions(element.formatStyle ?: "")
        val value = numberToBigDecimal(arg).toDouble()
        var selected = -1
        for (index in options.indices) {
            if (value >= options[index].limit) {
                selected = index
            } else {
                break
            }
        }
        // Intervals are [limit_i, limit_{i+1}); values below the first limit
        // use the first message, matching the JDK ChoiceFormat behavior.
        val message = options[selected.coerceIn(0, options.size - 1)].message
        out.append(renderElements(parsePattern(message), arguments, locale))
    }

    // MARK: - Pattern parsing

    private class FormatElement(
        val literal: String,
        val isArgument: Boolean,
        val rawText: String,
        val argIndex: Int,
        val formatType: String?,
        val formatStyle: String?,
        val numberStyleKind: NumberStyleKind,
        val numberPattern: NumberPattern?,
        val choiceOptions: List<ChoiceOption>?,
    ) {
        companion object {
            fun literalElement(text: String) = FormatElement(
                literal = text, isArgument = false, rawText = "", argIndex = -1,
                formatType = null, formatStyle = null,
                numberStyleKind = NumberStyleKind.NONE,
                numberPattern = null, choiceOptions = null,
            )
        }
    }

    private enum class NumberStyleKind { NONE, DEFAULT, INTEGER, PERCENT, CURRENCY, CUSTOM }

    private class ChoiceOption(val limit: Double, val message: String)

    private fun parsePattern(pattern: String): List<FormatElement> {
        val elements = mutableListOf<FormatElement>()
        val literal = StringBuilder()
        var i = 0
        fun flushLiteral() {
            if (literal.isNotEmpty()) {
                elements.add(FormatElement.literalElement(literal.toString()))
                literal.setLength(0)
            }
        }
        while (i < pattern.length) {
            val ch = pattern[i]
            when {
                ch == '\'' -> {
                    if (i + 1 < pattern.length && pattern[i + 1] == '\'') {
                        literal.append('\'')
                        i += 2
                    } else {
                        // Quoted literal runs until the next apostrophe; an
                        // unclosed quote quotes the rest of the pattern (JDK).
                        i++
                        while (i < pattern.length) {
                            if (pattern[i] == '\'') {
                                if (i + 1 < pattern.length && pattern[i + 1] == '\'') {
                                    literal.append('\'')
                                    i += 2
                                } else {
                                    i++
                                    break
                                }
                            } else {
                                literal.append(pattern[i])
                                i++
                            }
                        }
                    }
                }
                ch == '{' -> {
                    flushLiteral()
                    val (element, next) = parseArgumentElement(pattern, i)
                    elements.add(element)
                    i = next
                }
                ch == '}' -> throw IllegalArgumentException(
                    "Unmatched closing brace '}' in the pattern \"$pattern\""
                )
                else -> {
                    literal.append(ch)
                    i++
                }
            }
        }
        flushLiteral()
        return elements
    }

    private fun parseArgumentElement(pattern: String, start: Int): Pair<FormatElement, Int> {
        var i = start + 1
        val numberStart = i
        while (i < pattern.length && pattern[i].isDigit()) {
            i++
        }
        val numberText = pattern.substring(numberStart, i)
        if (numberText.isEmpty()) {
            throw IllegalArgumentException(
                "can't parse argument number in \"$pattern\" at offset $start"
            )
        }
        val argIndex = numberText.toIntOrNull()
            ?: throw IllegalArgumentException("can't parse argument number in \"$pattern\"")
        var formatType: String? = null
        var formatStyle: String? = null
        var braceConsumed = false
        if (i < pattern.length && pattern[i] == ',') {
            i++
            val typeStart = i
            while (i < pattern.length && pattern[i] != ',' && pattern[i] != '}') {
                i++
            }
            formatType = pattern.substring(typeStart, i)
            if (i < pattern.length && pattern[i] == ',') {
                i++
                // The style extends to the matching '}', honoring nested
                // braces so choice messages like "0#{1}|1#{2}" parse fully.
                val styleStart = i
                var depth = 1
                while (i < pattern.length && depth > 0) {
                    when (pattern[i]) {
                        '{' -> depth++
                        '}' -> depth--
                        else -> {}
                    }
                    if (depth > 0) i++
                }
                if (depth != 0) {
                    throw IllegalArgumentException("Unmatched braces in the pattern \"$pattern\"")
                }
                formatStyle = pattern.substring(styleStart, i)
                i++ // consume '}'
                braceConsumed = true
            }
        }
        if (!braceConsumed) {
            if (i >= pattern.length || pattern[i] != '}') {
                throw IllegalArgumentException("Unmatched braces in the pattern \"$pattern\"")
            }
            i++ // consume '}'
        }
        val rawText = pattern.substring(start, i)

        val normalizedType = formatType?.trim()?.lowercase()
        val elementType = when {
            normalizedType.isNullOrEmpty() -> null
            normalizedType == FORMAT_NUMBER -> FORMAT_NUMBER
            normalizedType == FORMAT_DATE -> FORMAT_DATE
            normalizedType == FORMAT_TIME -> FORMAT_TIME
            normalizedType == FORMAT_CHOICE -> FORMAT_CHOICE
            else -> throw IllegalArgumentException(
                "MessageFormat pattern has invalid format type \"$normalizedType\""
            )
        }

        var numberStyleKind = NumberStyleKind.NONE
        var numberPattern: NumberPattern? = null
        var choiceOptions: List<ChoiceOption>? = null
        when (elementType) {
            FORMAT_NUMBER -> {
                val style = formatStyle
                numberStyleKind = when {
                    style.isNullOrEmpty() -> NumberStyleKind.DEFAULT
                    style.equals("integer", ignoreCase = true) -> NumberStyleKind.INTEGER
                    style.equals("percent", ignoreCase = true) -> NumberStyleKind.PERCENT
                    style.equals("currency", ignoreCase = true) -> NumberStyleKind.CURRENCY
                    else -> NumberStyleKind.CUSTOM
                }
                if (numberStyleKind == NumberStyleKind.CUSTOM) {
                    // Eager validation like the JDK's DecimalFormat construction.
                    numberPattern = parseNumberPattern(style!!)
                }
            }
            FORMAT_CHOICE -> {
                choiceOptions = parseChoiceOptions(formatStyle ?: "")
            }
            else -> {}
        }

        return FormatElement(
            literal = "",
            isArgument = true,
            rawText = rawText,
            argIndex = argIndex,
            formatType = elementType,
            formatStyle = formatStyle,
            numberStyleKind = numberStyleKind,
            numberPattern = numberPattern,
            choiceOptions = choiceOptions,
        ) to i
    }

    private fun parseChoiceOptions(choiceStyle: String): List<ChoiceOption> {
        val options = mutableListOf<ChoiceOption>()
        var previousLimit = Double.NEGATIVE_INFINITY
        for (part in choiceStyle.split('|')) {
            val hash = part.indexOf('#')
            if (hash < 0) {
                throw IllegalArgumentException("Missing '#' in choice option \"$part\"")
            }
            val limitText = part.substring(0, hash).trim()
            val limit = limitText.toDoubleOrNull()
                ?: throw IllegalArgumentException("can't parse choice limit \"$limitText\"")
            if (limit <= previousLimit) {
                throw IllegalArgumentException(
                    "Incorrect order of intervals, must be in ascending order"
                )
            }
            previousLimit = limit
            options.add(ChoiceOption(limit, part.substring(hash + 1)))
        }
        if (options.isEmpty()) {
            throw IllegalArgumentException("Choice format style is empty")
        }
        return options
    }

    // MARK: - Number formatting

    private class NumberPatternBody(
        val prefix: String,
        val suffix: String,
        val multiplier: Int,
        val grouping: Boolean,
        val minIntDigits: Int,
        val minFracDigits: Int,
        val maxFracDigits: Int,
        val scientific: Boolean,
        val expMinDigits: Int,
        val expAlwaysSign: Boolean,
        val expLowercase: Boolean,
    )

    private class NumberPattern(
        val positive: NumberPatternBody,
        val negative: NumberPatternBody?,
    )

    private fun parseNumberPattern(pattern: String): NumberPattern {
        // Split at the first unquoted ';' into positive/negative subpatterns.
        var semi = -1
        var inQuote = false
        var i = 0
        while (i < pattern.length) {
            val ch = pattern[i]
            if (ch == '\'') {
                if (i + 1 < pattern.length && pattern[i + 1] == '\'') {
                    i += 2
                    continue
                }
                inQuote = !inQuote
                i++
                continue
            }
            if (ch == ';' && !inQuote) {
                semi = i
                break
            }
            i++
        }
        val positiveText = if (semi >= 0) pattern.substring(0, semi) else pattern
        val negativeText = if (semi >= 0) pattern.substring(semi + 1) else null
        val negativeBody = negativeText?.let {
            // A second unquoted ';' is rejected by the JDK.
            var nestedQuote = false
            var k = 0
            var found = false
            while (k < it.length) {
                val ch = it[k]
                if (ch == '\'') {
                    if (k + 1 < it.length && it[k + 1] == '\'') {
                        k += 2
                        continue
                    }
                    nestedQuote = !nestedQuote
                    k++
                    continue
                }
                if (ch == ';' && !nestedQuote) {
                    found = true
                    break
                }
                k++
            }
            if (found) {
                throw IllegalArgumentException("Unparseable number pattern \"$pattern\"")
            }
            parseNumberPatternBody(it)
        }
        return NumberPattern(parseNumberPatternBody(positiveText), negativeBody)
    }

    private fun parseNumberPatternBody(text: String): NumberPatternBody {
        if (text.isEmpty()) {
            throw IllegalArgumentException("Unparseable number pattern \"\"")
        }
        // Locate the numeric core: first unquoted '0' or '#'.
        var coreStart = -1
        var quote = false
        var scan = 0
        while (scan < text.length) {
            val ch = text[scan]
            if (ch == '\'') {
                if (scan + 1 < text.length && text[scan + 1] == '\'') {
                    scan += 2
                    continue
                }
                quote = !quote
                scan++
                continue
            }
            if (!quote && (ch == '0' || ch == '#')) {
                coreStart = scan
                break
            }
            scan++
        }
        if (coreStart < 0) {
            throw IllegalArgumentException("Unparseable number pattern \"$text\"")
        }
        val (prefix, prefixMult) = resolvePatternAffix(text.substring(0, coreStart))

        var k = coreStart
        var grouping = false
        var minInt = 0
        while (k < text.length) {
            when (text[k]) {
                '0' -> {
                    minInt++
                    k++
                }
                '#' -> k++
                ',' -> {
                    grouping = true
                    k++
                }
                else -> break
            }
        }
        var minFrac = 0
        var maxFrac = 0
        if (k < text.length && text[k] == '.') {
            k++
            while (k < text.length) {
                when (text[k]) {
                    '0' -> {
                        minFrac++
                        maxFrac++
                        k++
                    }
                    '#' -> {
                        maxFrac++
                        k++
                    }
                    else -> break
                }
            }
        }
        var scientific = false
        var expMin = 0
        var expSign = false
        var expLower = false
        if (k < text.length && (text[k] == 'E' || text[k] == 'e')) {
            var m = k + 1
            var sign = false
            if (m < text.length && (text[m] == '+' || text[m] == '-')) {
                sign = text[m] == '+'
                m++
            }
            var expDigits = 0
            var expZeros = 0
            var n = m
            while (n < text.length && (text[n] == '0' || text[n] == '#')) {
                if (text[n] == '0') expZeros++
                expDigits++
                n++
            }
            if (expDigits > 0) {
                scientific = true
                expMin = expZeros
                expSign = sign
                expLower = text[k] == 'e'
                k = n
            }
        }
        val (suffix, suffixMult) = resolvePatternAffix(text.substring(k))

        return NumberPatternBody(
            prefix = prefix,
            suffix = suffix,
            multiplier = prefixMult * suffixMult,
            grouping = grouping,
            minIntDigits = minInt,
            minFracDigits = minFrac,
            maxFracDigits = maxFrac,
            scientific = scientific,
            expMinDigits = expMin,
            expAlwaysSign = expSign,
            expLowercase = expLower,
        )
    }

    /** Resolves quoted literals in an affix; unquoted `%`/`‰` set the multiplier. */
    private fun resolvePatternAffix(raw: String): Pair<String, Int> {
        val out = StringBuilder()
        var multiplier = 1
        var i = 0
        while (i < raw.length) {
            val ch = raw[i]
            when {
                ch == '\'' -> {
                    if (i + 1 < raw.length && raw[i + 1] == '\'') {
                        out.append('\'')
                        i += 2
                    } else {
                        i++
                        while (i < raw.length) {
                            if (raw[i] == '\'') {
                                if (i + 1 < raw.length && raw[i + 1] == '\'') {
                                    out.append('\'')
                                    i += 2
                                } else {
                                    i++
                                    break
                                }
                            } else {
                                out.append(raw[i])
                                i++
                            }
                        }
                    }
                }
                ch == '%' -> {
                    multiplier *= 100
                    out.append('%')
                    i++
                }
                ch == '‰' -> {
                    multiplier *= 1000
                    out.append('‰')
                    i++
                }
                else -> {
                    out.append(ch)
                    i++
                }
            }
        }
        return out.toString() to multiplier
    }

    private fun numberToBigDecimal(value: Number): BigDecimal = when (value) {
        is BigDecimal -> value
        is BigInteger -> BigDecimal(value.toString())
        is Double -> BigDecimal(value)
        is Float -> BigDecimal(value.toDouble())
        else -> BigDecimal(value.toString())
    }

    private fun isNonFinite(value: Number): Boolean = when (value) {
        is Double -> value.isNaN() || value.isInfinite()
        is Float -> value.isNaN() || value.isInfinite()
        else -> false
    }

    private fun nonFiniteText(value: Number): String = when (value) {
        is Double -> when {
            value.isNaN() -> "NaN"
            value > 0 -> "∞"
            else -> "-∞"
        }
        is Float -> when {
            value.isNaN() -> "NaN"
            value > 0 -> "∞"
            else -> "-∞"
        }
        else -> value.toString()
    }

    private fun isNegativeValue(value: BigDecimal): Boolean =
        value.signum() < 0 || value.toString().startsWith("-")

    private fun formatNumberValue(
        value: BigDecimal,
        pattern: NumberPattern,
        info: JavaTextNumberLocale,
    ): String {
        val negative = isNegativeValue(value)
        val body = if (negative && pattern.negative != null) pattern.negative!! else pattern.positive
        val rendered = formatNumberWithBody(value, body, info)
        return if (negative && pattern.negative == null) "-$rendered" else rendered
    }

    private fun formatNumberWithBody(
        value: BigDecimal,
        body: NumberPatternBody,
        info: JavaTextNumberLocale,
    ): String {
        var scaled = value
        if (body.multiplier != 1) {
            scaled = scaled.multiply(BigDecimal(body.multiplier.toString()))
        }
        return if (body.scientific) {
            formatScientific(scaled, body, info)
        } else {
            formatPlainDecimal(scaled, body, info)
        }
    }

    private fun formatPlainDecimal(
        value: BigDecimal,
        body: NumberPatternBody,
        info: JavaTextNumberLocale,
    ): String {
        val rounded = value.setScale(body.maxFracDigits, RoundingMode.HALF_EVEN)
        val parts = decimalDigits(rounded)
        var intPart = parts.intDigits.trimStart('0')
        if (intPart.isEmpty()) intPart = "0"
        intPart = intPart.padStart(body.minIntDigits, '0')
        var fracPart = parts.fracDigits.trimEnd('0')
        if (fracPart.length < body.minFracDigits) {
            fracPart = fracPart.padEnd(body.minFracDigits, '0')
        }
        if (body.grouping && intPart.length > 3) {
            intPart = insertGrouping(intPart, info.groupingSeparator)
        }
        val prefix = body.prefix.replace("¤", info.currencySymbol)
        val suffix = body.suffix.replace("¤", info.currencySymbol)
        val core = StringBuilder()
        core.append(intPart)
        if (fracPart.isNotEmpty()) {
            core.append(info.decimalSeparator)
            core.append(fracPart)
        }
        return prefix + core.toString() + suffix
    }

    private fun formatScientific(
        value: BigDecimal,
        body: NumberPatternBody,
        info: JavaTextNumberLocale,
    ): String {
        if (value.signum() == 0) {
            // Zero renders with a zero mantissa, e.g. "0.00E0".
            val frac = "0".repeat(body.maxFracDigits.coerceAtLeast(body.minFracDigits))
            val mantissa = "0" + (if (frac.isNotEmpty()) "." + frac else "")
            return body.prefix.replace("¤", info.currencySymbol) + mantissa +
                scientificSuffix(0, body, info)
        }
        // decimal exponent of the first significant digit.
        val probe = decimalPointInfo(value)
        val exp10 = probe.pointPos - probe.firstSignificant - 1
        var mantissa = value.movePointLeft(exp10)
        mantissa = mantissa.setScale(body.maxFracDigits, RoundingMode.HALF_EVEN)
        var finalExp = exp10
        if (mantissa.compareTo(BigDecimal.TEN) >= 0) {
            mantissa = mantissa.movePointLeft(1)
            finalExp++
        }
        val parts = decimalDigits(mantissa)
        var intPart = parts.intDigits.trimStart('0')
        if (intPart.isEmpty()) intPart = "0"
        intPart = intPart.padStart(body.minIntDigits.coerceAtLeast(1), '0')
        var fracPart = parts.fracDigits.trimEnd('0')
        if (fracPart.length < body.minFracDigits) {
            fracPart = fracPart.padEnd(body.minFracDigits, '0')
        }
        val prefix = body.prefix.replace("¤", info.currencySymbol)
        val core = StringBuilder()
        core.append(intPart)
        if (fracPart.isNotEmpty()) {
            core.append(info.decimalSeparator)
            core.append(fracPart)
        }
        return prefix + core.toString() + scientificSuffix(finalExp, body, info)
    }

    private fun scientificSuffix(exp: Int, body: NumberPatternBody, info: JavaTextNumberLocale): String {
        val marker = if (body.expLowercase) 'e' else 'E'
        val sign = when {
            exp < 0 -> "-"
            body.expAlwaysSign -> "+"
            else -> ""
        }
        val digits = exp.toString().removePrefix("-").padStart(body.expMinDigits, '0')
        return marker + sign + digits + body.suffix.replace("¤", info.currencySymbol)
    }

    private class DecimalParts(val intDigits: String, val fracDigits: String)

    /** Splits a BigDecimal's canonical string form into integer/fraction digits. */
    private fun decimalDigits(value: BigDecimal): DecimalParts {
        val info = decimalPointInfo(value)
        val digits = info.digits
        val pointPos = info.pointPos
        return when {
            pointPos <= 0 -> DecimalParts("0", "0".repeat(-pointPos) + digits)
            pointPos >= digits.length -> DecimalParts(digits + "0".repeat(pointPos - digits.length), "")
            else -> DecimalParts(digits.substring(0, pointPos), digits.substring(pointPos))
        }
    }

    private class DigitInfo(val digits: String, val pointPos: Int, val firstSignificant: Int)

    /**
     * Parses `BigDecimal.toString()` (plain or scientific) into a digit string
     * `d` and point position `p` such that value = 0.d * 10^p (magnitude only;
     * the sign is stripped).
     */
    private fun decimalPointInfo(value: BigDecimal): DigitInfo {
        var s = value.toString()
        if (s.startsWith("-")) s = s.substring(1)
        var exp = 0
        var eIndex = s.indexOf('E')
        if (eIndex < 0) eIndex = s.indexOf('e')
        if (eIndex >= 0) {
            exp = s.substring(eIndex + 1).toInt()
            s = s.substring(0, eIndex)
        }
        val dot = s.indexOf('.')
        val intRaw = if (dot >= 0) s.substring(0, dot) else s
        val fracRaw = if (dot >= 0) s.substring(dot + 1) else ""
        val digits = intRaw + fracRaw
        val pointPos = intRaw.length + exp
        var firstSig = 0
        while (firstSig < digits.length && digits[firstSig] == '0') firstSig++
        return DigitInfo(digits, pointPos, firstSig)
    }

    private fun insertGrouping(intDigits: String, separator: String): String {
        val groups = mutableListOf<String>()
        var end = intDigits.length
        while (end > 0) {
            val start = maxOf(0, end - 3)
            groups.add(intDigits.substring(start, end))
            end = start
        }
        return groups.reversed().joinToString(separator)
    }

    // MARK: - Locale data for number/currency/percent

    private class JavaTextNumberLocale(
        val groupingSeparator: String,
        val decimalSeparator: String,
        val percentPrefix: String,
        val percentSuffix: String,
        val currencyPattern: String,
        val currencySymbol: String,
    )

    private fun localeKeyParts(locale: Locale): Pair<String, String> {
        var language = locale.language.lowercase()
        var country = locale.country.uppercase()
        for (separator in charArrayOf('_', '-')) {
            val index = language.indexOf(separator)
            if (index >= 0) {
                val tail = language.substring(index + 1)
                language = language.substring(0, index)
                if (country.isEmpty()) {
                    country = tail.uppercase()
                }
            }
        }
        return language to country
    }

    private fun numberLocaleFor(locale: Locale): JavaTextNumberLocale {
        val (language, country) = localeKeyParts(locale)
        if (country.isNotEmpty()) {
            NUMBER_LOCALE_EXACT["${language}_$country"]?.let { return it }
        }
        return NUMBER_LOCALE_LANG[language] ?: NUMBER_LOCALE_EN
    }

    private val NUMBER_LOCALE_EN = JavaTextNumberLocale(",", ".", "", "%", "¤#,##0.00", "$")
    private val NUMBER_LOCALE_EN_GB = JavaTextNumberLocale(",", ".", "", "%", "¤#,##0.00", "£")
    private val NUMBER_LOCALE_JA = JavaTextNumberLocale(",", ".", "", "%", "¤#,##0", "￥")
    private val NUMBER_LOCALE_ZH = JavaTextNumberLocale(",", ".", "", "%", "¤#,##0.00", "¥")
    private val NUMBER_LOCALE_ZH_TW = JavaTextNumberLocale(",", ".", "", "%", "¤#,##0.00", "$")
    private val NUMBER_LOCALE_ZH_HK = JavaTextNumberLocale(",", ".", "", "%", "¤#,##0.00", "HK$")
    // NBSP = \u00A0, NNBSP = \u202F, LRM = \u200E (kept as escapes for readability).
    private val NUMBER_LOCALE_DE = JavaTextNumberLocale(".", ",", "", "\u00A0%", "#,##0.00\u00A0¤", "€")
    private val NUMBER_LOCALE_FR = JavaTextNumberLocale("\u202F", ",", "", "\u00A0%", "#,##0.00\u00A0¤", "¤")
    private val NUMBER_LOCALE_FR_CA = JavaTextNumberLocale("\u00A0", ",", "", "\u00A0%", "#,##0.00\u00A0¤", "$")
    private val NUMBER_LOCALE_ES = JavaTextNumberLocale(".", ",", "", "\u00A0%", "#,##0.00\u00A0¤", "¤")
    private val NUMBER_LOCALE_ES_MX = JavaTextNumberLocale(",", ".", "", "%", "¤#,##0.00", "$")
    private val NUMBER_LOCALE_IT = JavaTextNumberLocale(".", ",", "", "%", "#,##0.00\u00A0¤", "¤")
    private val NUMBER_LOCALE_PT = JavaTextNumberLocale(".", ",", "", "%", "¤\u00A0#,##0.00", "¤")
    private val NUMBER_LOCALE_PT_PT = JavaTextNumberLocale("\u00A0", ",", "", "%", "#,##0.00\u00A0€", "€")
    private val NUMBER_LOCALE_PT_BR = JavaTextNumberLocale(".", ",", "", "%", "¤#,##0.00", "R$")
    private val NUMBER_LOCALE_RU = JavaTextNumberLocale("\u00A0", ",", "", "\u00A0%", "#,##0.00\u00A0¤", "¤")
    private val NUMBER_LOCALE_PL = JavaTextNumberLocale("\u00A0", ",", "", "%", "#,##0.00\u00A0¤", "¤")
    private val NUMBER_LOCALE_SV = JavaTextNumberLocale("\u00A0", ",", "", "\u00A0%", "#,##0.00\u00A0¤", "¤")
    private val NUMBER_LOCALE_NL = JavaTextNumberLocale(".", ",", "", "%", "¤\u00A0#,##0.00", "¤")
    private val NUMBER_LOCALE_TR = JavaTextNumberLocale(".", ",", "%", "", "¤#,##0.00", "¤")
    private val NUMBER_LOCALE_AR = JavaTextNumberLocale(",", ".", "", "\u200E%\u200E", "#,##0.00\u00A0¤", "¤")
    private val NUMBER_LOCALE_HI = NUMBER_LOCALE_EN

    private val NUMBER_LOCALE_LANG: Map<String, JavaTextNumberLocale> = mapOf(
        "en" to NUMBER_LOCALE_EN,
        "ja" to NUMBER_LOCALE_JA,
        "de" to NUMBER_LOCALE_DE,
        "fr" to NUMBER_LOCALE_FR,
        "zh" to NUMBER_LOCALE_ZH,
        "ko" to NUMBER_LOCALE_EN,
        "es" to NUMBER_LOCALE_ES,
        "it" to NUMBER_LOCALE_IT,
        "pt" to NUMBER_LOCALE_PT,
        "ru" to NUMBER_LOCALE_RU,
        "ar" to NUMBER_LOCALE_AR,
        "hi" to NUMBER_LOCALE_HI,
        "nl" to NUMBER_LOCALE_NL,
        "sv" to NUMBER_LOCALE_SV,
        "tr" to NUMBER_LOCALE_TR,
        "pl" to NUMBER_LOCALE_PL,
    )

    private val NUMBER_LOCALE_EXACT: Map<String, JavaTextNumberLocale> = mapOf(
        "en_GB" to NUMBER_LOCALE_EN_GB,
        "en_IN" to NUMBER_LOCALE_EN_GB,
        "en_IE" to NUMBER_LOCALE_EN,
        "en_NZ" to NUMBER_LOCALE_EN_GB,
        "en_SG" to NUMBER_LOCALE_EN_GB,
        "en_HK" to NUMBER_LOCALE_EN_GB,
        "en_ZA" to NUMBER_LOCALE_EN_GB,
        "en_001" to NUMBER_LOCALE_EN_GB,
        "en_CA" to NUMBER_LOCALE_EN,
        "en_US" to NUMBER_LOCALE_EN,
        "en_AU" to NUMBER_LOCALE_EN,
        "en_PH" to NUMBER_LOCALE_EN,
        "de_CH" to JavaTextNumberLocale("'", ".", "", "%", "¤\u00A0#,##0.00", "CHF"),
        "fr_CA" to NUMBER_LOCALE_FR_CA,
        "zh_TW" to NUMBER_LOCALE_ZH_TW,
        "zh_HK" to NUMBER_LOCALE_ZH_HK,
        "zh_MO" to NUMBER_LOCALE_ZH_HK,
        "pt_PT" to NUMBER_LOCALE_PT_PT,
        "pt_BR" to NUMBER_LOCALE_PT_BR,
        "es_MX" to NUMBER_LOCALE_ES_MX,
        "es_ES" to NUMBER_LOCALE_ES,
        "es_AR" to NUMBER_LOCALE_ES,
        "ja_JP" to NUMBER_LOCALE_JA,
        "de_DE" to NUMBER_LOCALE_DE,
        "fr_FR" to NUMBER_LOCALE_FR,
        "zh_CN" to NUMBER_LOCALE_ZH,
        "ko_KR" to NUMBER_LOCALE_EN,
        "it_IT" to NUMBER_LOCALE_IT,
        "ru_RU" to NUMBER_LOCALE_RU,
        "hi_IN" to NUMBER_LOCALE_HI,
        "nl_NL" to NUMBER_LOCALE_NL,
        "sv_SE" to NUMBER_LOCALE_SV,
        "tr_TR" to NUMBER_LOCALE_TR,
        "pl_PL" to NUMBER_LOCALE_PL,
        "ar_SA" to NUMBER_LOCALE_AR,
    )

    public companion object {
        /** Static form equivalent to `MessageFormat(pattern).format(arguments)`. */
        public fun format(pattern: String, vararg arguments: Any?): String =
            MessageFormat(pattern).format(*arguments)

        public fun format(pattern: String, arguments: Array<out Any?>): String =
            MessageFormat(pattern).format(arguments)
    }
}

@KsSymbolName("__kk_messageformat_datetime")
private external fun __messageFormatDateTime(kind: Int, style: Int, epochMillis: Long, locale: Locale): String

@KsSymbolName("__kk_simple_date_format_format")
private external fun __simpleDateFormatFormat(pattern: String, epochMillis: Long, locale: Locale): String

private const val DEFAULT_NUMBER_STYLE = "#,##0.###"

private const val FORMAT_NUMBER = "number"
private const val FORMAT_DATE = "date"
private const val FORMAT_TIME = "time"
private const val FORMAT_CHOICE = "choice"

private const val DATETIME_KIND_DATE = 0
private const val DATETIME_KIND_TIME = 1
private const val DATETIME_KIND_BOTH = 2

private const val DATETIME_STYLE_SHORT = 0
private const val DATETIME_STYLE_MEDIUM = 1
private const val DATETIME_STYLE_LONG = 2
private const val DATETIME_STYLE_FULL = 3
