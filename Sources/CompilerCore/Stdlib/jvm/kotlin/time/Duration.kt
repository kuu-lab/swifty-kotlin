package kotlin.time

@JvmInline
public value class Duration private constructor(private val rawValue: Long) : Comparable<Duration> {
    public val inWholeNanoseconds: Long get() = toLong(DurationUnit.NANOSECONDS)
    public val inWholeMicroseconds: Long get() = toLong(DurationUnit.MICROSECONDS)
    public val inWholeMilliseconds: Long get() = toLong(DurationUnit.MILLISECONDS)
    public val inWholeSeconds: Long get() = toLong(DurationUnit.SECONDS)
    public val inWholeMinutes: Long get() = toLong(DurationUnit.MINUTES)
    public val inWholeHours: Long get() = toLong(DurationUnit.HOURS)
    public val inWholeDays: Long get() = toLong(DurationUnit.DAYS)

    @PublishedApi
    internal val hoursComponent: Int
        get() = if (isInfinite()) 0 else (inWholeHours % 24L).toInt()

    @PublishedApi
    internal val minutesComponent: Int
        get() = if (isInfinite()) 0 else (inWholeMinutes % 60L).toInt()

    @PublishedApi
    internal val secondsComponent: Int
        get() = if (isInfinite()) 0 else (inWholeSeconds % 60L).toInt()

    @PublishedApi
    internal val nanosecondsComponent: Int
        get() {
            if (isInfinite()) return 0
            val scale = durationStorageScale(rawValue)
            return ((durationValue(rawValue) % (NANOS_PER_SECOND / scale)) * scale).toInt()
        }

    public fun isNegative(): Boolean = rawValue < 0L
    public fun isPositive(): Boolean = rawValue > 0L
    public fun isInfinite(): Boolean = durationIsInfinite(rawValue)
    public fun isFinite(): Boolean = !isInfinite()

    public override fun compareTo(other: Duration): Int = compareDurationRaw(rawValue, other.rawValue)

    public operator fun plus(other: Duration): Duration = Duration(addDurationRaw(rawValue, other.rawValue))

    public operator fun minus(other: Duration): Duration = this + (-other)

    public operator fun unaryMinus(): Duration = negated()

    internal fun negated(): Duration = Duration(((-durationValue(rawValue)) shl 1) or (rawValue and 1L))

    public override fun toString(): String = durationToString(rawValue)

    public fun toDouble(unit: DurationUnit): Double = durationRawToDouble(rawValue, unit)

    public fun toLong(unit: DurationUnit): Long = durationRawToLong(rawValue, unit)

    public fun toInt(unit: DurationUnit): Int {
        val wholeValue = toLong(unit)
        return if (wholeValue < Int.MIN_VALUE.toLong()) Int.MIN_VALUE
            else if (wholeValue > Int.MAX_VALUE.toLong()) Int.MAX_VALUE
            else wholeValue.toInt()
    }

    public companion object {
        public val ZERO: Duration get() = Duration(0L)
        public val INFINITE: Duration get() = Duration(Long.MAX_VALUE)

        internal fun fromRawValue(rawValue: Long): Duration = Duration(rawValue)

        public fun parse(value: String): Duration {
            val parsed = durationJvmParseOrNullRaw(value, strictIso = false)
                ?: throw IllegalArgumentException("Invalid duration string format: '$value'.")
            return Duration(parsed)
        }

        public fun parseIsoString(value: String): Duration {
            val parsed = durationJvmParseOrNullRaw(value, strictIso = true)
                ?: throw IllegalArgumentException("Invalid ISO duration string format: '$value'.")
            return Duration(parsed)
        }

        public fun parseOrNull(value: String): Duration? {
            val parsed = durationJvmParseOrNullRaw(value, strictIso = false) ?: return null
            return Duration(parsed)
        }

        public fun parseIsoStringOrNull(value: String): Duration? {
            val parsed = durationJvmParseOrNullRaw(value, strictIso = true) ?: return null
            return Duration(parsed)
        }
    }
}

private class DurationJvmParsedNumber {
    var index: Int = 0
    var whole: Long = 0L
    var fraction: Double = 0.0
    var hasFraction: Boolean = false
    var overflow: Boolean = false
    var sign: Int = 1
}

private class DurationJvmParsedUnit(
    val order: Int,
    val unit: DurationUnit,
)

private fun durationJvmParseNumber(text: String, startIndex: Int, end: Int, allowSign: Boolean): DurationJvmParsedNumber? {
    var index = startIndex
    val result = DurationJvmParsedNumber()
    if (allowSign && index < end) {
        if (text[index] == '-') {
            result.sign = -1
            index += 1
        } else if (text[index] == '+') {
            index += 1
        }
    }

    val digitsStart = index
    while (index < end && text[index] == '0') index += 1
    while (index < end && text[index] >= '0' && text[index] <= '9') {
        val digit = text[index] - '0'
        if (!result.overflow) {
            if (result.whole > (Long.MAX_VALUE - digit) / 10L) {
                result.overflow = true
                result.whole = Long.MAX_VALUE
            } else {
                result.whole = result.whole * 10L + digit
            }
        }
        index += 1
    }
    if (index == digitsStart) return null

    if (index < end && text[index] == '.') {
        index += 1
        val fractionStart = index
        var fraction = 0.0
        var place = 10.0
        while (index < end && text[index] >= '0' && text[index] <= '9') {
            fraction += (text[index] - '0').toDouble() / place
            place *= 10.0
            index += 1
        }
        if (index == fractionStart) return null
        result.fraction = fraction
        result.hasFraction = true
    }
    result.index = index
    return result
}

private fun durationJvmApplySign(raw: Long, sign: Int): Long =
    if (sign >= 0) raw else ((-(raw shr 1)) shl 1) or (raw and 1L)

private fun durationJvmComponentRaw(number: DurationJvmParsedNumber, unit: DurationUnit): Long {
    val whole = durationRawFromLong(number.whole, unit)
    val fraction = durationRawFromDouble(number.fraction, durationUnitScale(unit))
    return durationJvmApplySign(addDurationRaw(whole, fraction), number.sign)
}

private fun durationJvmDefaultUnit(text: String, index: Int, end: Int): DurationJvmParsedUnit? {
    if (index >= end) return null
    val second = if (index + 1 < end) text[index + 1] else '\u0000'
    return when (text[index]) {
        'd' -> DurationJvmParsedUnit(6, DurationUnit.DAYS)
        'h' -> DurationJvmParsedUnit(5, DurationUnit.HOURS)
        'm' -> if (second == 's') DurationJvmParsedUnit(2, DurationUnit.MILLISECONDS) else DurationJvmParsedUnit(4, DurationUnit.MINUTES)
        's' -> DurationJvmParsedUnit(3, DurationUnit.SECONDS)
        'u' -> if (second == 's') DurationJvmParsedUnit(1, DurationUnit.MICROSECONDS) else null
        'n' -> if (second == 's') DurationJvmParsedUnit(0, DurationUnit.NANOSECONDS) else null
        else -> null
    }
}

private fun durationJvmIsoUnit(ch: Char, inTime: Boolean): DurationJvmParsedUnit? = when {
    ch == 'D' && !inTime -> DurationJvmParsedUnit(6, DurationUnit.DAYS)
    ch == 'H' && inTime -> DurationJvmParsedUnit(5, DurationUnit.HOURS)
    ch == 'M' && inTime -> DurationJvmParsedUnit(4, DurationUnit.MINUTES)
    ch == 'S' && inTime -> DurationJvmParsedUnit(3, DurationUnit.SECONDS)
    else -> null
}

private fun durationJvmParseIsoFormat(text: String, startIndex: Int): Long? {
    var index = startIndex
    if (index >= text.length) return null
    var inTime = false
    var prevOrder = Int.MAX_VALUE
    var hasComponent = false
    var total = 0L

    while (index < text.length) {
        if (text[index] == 'T') {
            if (inTime) return null
            index += 1
            if (index == text.length) return null
            inTime = true
            continue
        }

        val number = durationJvmParseNumber(text, index, text.length, allowSign = true) ?: return null
        index = number.index
        if (index >= text.length) return null
        if (number.hasFraction && text[index] != 'S') return null
        val unit = durationJvmIsoUnit(text[index], inTime) ?: return null
        if (prevOrder <= unit.order) return null
        prevOrder = unit.order
        hasComponent = true
        index += 1
        total = addDurationRaw(total, durationJvmComponentRaw(number, unit.unit))
    }

    return if (hasComponent) total else null
}

private fun durationJvmParseDefaultFormat(text: String, startIndex: Int, hasSign: Boolean): Long? {
    var index = startIndex
    var end = text.length
    var allowSpaces = !hasSign

    if (hasSign && index < end && text[index] == '(' && text[end - 1] == ')') {
        allowSpaces = true
        index += 1
        end -= 1
        if (index >= end) return null
    }

    var total = 0L
    var prevOrder = Int.MAX_VALUE
    var hasComponent = false
    while (index < end) {
        if (allowSpaces && hasComponent) {
            while (index < end && text[index] == ' ') index += 1
        }

        val number = durationJvmParseNumber(text, index, end, allowSign = false) ?: return null
        if (number.overflow) return null
        index = number.index
        if (index >= end) return null
        val unit = durationJvmDefaultUnit(text, index, end) ?: return null
        if (prevOrder <= unit.order) return null
        prevOrder = unit.order
        hasComponent = true
        index += if (unit.unit == DurationUnit.MILLISECONDS || unit.unit == DurationUnit.MICROSECONDS || unit.unit == DurationUnit.NANOSECONDS) 2 else 1

        if (number.hasFraction && index < end) return null
        total = addDurationRaw(total, durationJvmComponentRaw(number, unit.unit))
    }

    return if (hasComponent) total else null
}

private fun durationJvmIsInfinity(text: String, startIndex: Int): Boolean {
    val infinity = "Infinity"
    if (text.length - startIndex != infinity.length) return false
    var index = 0
    while (index < infinity.length) {
        val expected = infinity[index]
        val actual = text[startIndex + index]
        if (actual.lowercaseChar() != expected.lowercaseChar()) return false
        index += 1
    }
    return true
}

private fun durationJvmParseOrNullRaw(value: String, strictIso: Boolean): Long? {
    if (value.isEmpty()) return null
    var index = 0
    var isNegative = false
    if (value[index] == '-') {
        isNegative = true
        index += 1
    } else if (value[index] == '+') {
        index += 1
    }
    val hasSign = index > 0
    if (index >= value.length) return null

    val parsedOrNull = if (value[index] == 'P') {
        durationJvmParseIsoFormat(value, index + 1)
    } else if (strictIso) {
        null
    } else if (durationJvmIsInfinity(value, index)) {
        Long.MAX_VALUE
    } else {
        durationJvmParseDefaultFormat(value, index, hasSign)
    }
    if (parsedOrNull == null) return null
    val parsed: Long = parsedOrNull
    return if (isNegative) durationJvmApplySign(parsed, -1) else parsed
}

public fun Int.toDuration(unit: DurationUnit): Duration = Duration.fromRawValue(durationRawFromLong(this.toLong(), unit))

public fun Long.toDuration(unit: DurationUnit): Duration = Duration.fromRawValue(durationRawFromLong(this, unit))

public fun Double.toDuration(unit: DurationUnit): Duration = Duration.fromRawValue(durationRawFromDouble(this, durationUnitScale(unit)))
