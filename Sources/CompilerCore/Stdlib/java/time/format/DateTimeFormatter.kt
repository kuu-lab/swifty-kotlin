package java.time.format

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.DateTimeException
import java.time.javaTimeTwoDigits

/** Formats the bundled java.time value types using ISO or a common Java pattern. */
public class DateTimeFormatter private constructor(
    private val pattern: String,
    private val isoKind: Int,
) {
    public fun format(value: LocalDate): String =
        if (isoKind == 1) value.toString() else formatPattern(value, null, null)

    public fun format(value: LocalTime): String =
        if (isoKind == 2) value.toString() else formatPattern(null, value, null)

    public fun format(value: LocalDateTime): String =
        if (isoKind == 3) value.toString() else formatPattern(value.date, value.time, null)

    public fun format(value: OffsetDateTime): String = when (isoKind) {
        1 -> value.toLocalDate().toString()
        2 -> value.toLocalTime().toString()
        3 -> value.toLocalDateTime().toString()
        4 -> value.toInstant().toString()
        5 -> value.toString()
        6 -> value.toLocalDate().toString() + value.offset.toString()
        7 -> value.toLocalTime().toString() + value.offset.toString()
        else -> formatPattern(value.toLocalDate(), value.toLocalTime(), value.offset)
    }

    public fun format(value: Instant): String {
        if (isoKind != 4) throw DateTimeException("Unable to format Instant with this formatter")
        return value.toString()
    }

    private fun formatPattern(date: LocalDate?, time: LocalTime?, offset: ZoneOffset?): String {
        val output = StringBuilder()
        var index = 0
        while (index < pattern.length) {
            val current = pattern[index]
            if (current == '\'') {
                index += 1
                while (index < pattern.length && pattern[index] != '\'') {
                    output.append(pattern[index])
                    index += 1
                }
                if (index < pattern.length) index += 1
                continue
            }
            var end = index + 1
            while (end < pattern.length && pattern[end] == current) end += 1
            val count = end - index
            output.append(formatField(current, count, date, time, offset))
            index = end
        }
        return output.toString()
    }

    private fun formatField(
        symbol: Char,
        count: Int,
        date: LocalDate?,
        time: LocalTime?,
        offset: ZoneOffset?,
    ): String {
        val numeric: Int? = when (symbol) {
            'y', 'u' -> date?.year
            'M', 'L' -> date?.monthValue
            'd' -> date?.dayOfMonth
            'D' -> date?.dayOfYear
            'H' -> time?.hour
            'h' -> time?.let { if (it.hour % 12 == 0) 12 else it.hour % 12 }
            'm' -> time?.minute
            's' -> time?.second
            'S' -> time?.nano?.let { it / 1_000_000 }
            'n' -> time?.nano
            else -> null
        }
        if (symbol == 'a' && time != null) return if (time.hour < 12) "AM" else "PM"
        if ((symbol == 'X' || symbol == 'x') && offset != null) return javaTimeFormatOffsetX(offset, symbol, count)
        if (symbol == 'Z' && offset != null) return javaTimeFormatOffsetZ(offset, count)
        if ((symbol == 'M' || symbol == 'L') && count >= 3 && date != null) {
            return if (count == 3) javaTimeMonthShortName(date.monthValue) else javaTimeMonthName(date.monthValue)
        }
        if (numeric == null) return symbol.toString().repeat(count)
        if (symbol == 'y' && date != null && count == 2) {
            return javaTimeTwoDigits(date.year % 100)
        }
        val raw = if (symbol == 'y' || symbol == 'u') {
            if (numeric < 0) "-" + (-numeric).toString() else numeric.toString()
        } else {
            numeric.toString()
        }
        return if (raw.length < count) "0".repeat(count - raw.length) + raw else raw
    }

    public companion object {
        public val ISO_DATE: DateTimeFormatter = DateTimeFormatter("yyyy-MM-dd", 1)
        public val ISO_LOCAL_DATE: DateTimeFormatter = DateTimeFormatter("yyyy-MM-dd", 1)
        public val ISO_LOCAL_TIME: DateTimeFormatter = DateTimeFormatter("HH:mm:ss", 2)
        public val ISO_TIME: DateTimeFormatter = ISO_LOCAL_TIME
        public val ISO_LOCAL_DATE_TIME: DateTimeFormatter = DateTimeFormatter("yyyy-MM-dd'T'HH:mm:ss", 3)
        public val ISO_DATE_TIME: DateTimeFormatter = ISO_LOCAL_DATE_TIME
        public val ISO_INSTANT: DateTimeFormatter = DateTimeFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'", 4)
        public val ISO_OFFSET_DATE: DateTimeFormatter = DateTimeFormatter("yyyy-MM-dd", 6)
        public val ISO_OFFSET_TIME: DateTimeFormatter = DateTimeFormatter("HH:mm:ss", 7)
        public val ISO_OFFSET_DATE_TIME: DateTimeFormatter = DateTimeFormatter("yyyy-MM-dd'T'HH:mm:ss", 5)

        public fun ofPattern(pattern: String): DateTimeFormatter = DateTimeFormatter(pattern, 0)
    }
}

private fun javaTimeFormatOffsetX(offset: ZoneOffset, symbol: Char, count: Int): String {
    val total = offset.totalSeconds
    if (total == 0 && symbol == 'X') return "Z"
    val absolute = if (total < 0) -total else total
    val hours = absolute / 3_600
    val minutes = (absolute / 60) % 60
    val seconds = absolute % 60
    val sign = if (total < 0) "-" else "+"
    return when (count) {
        1 -> sign + javaTimeTwoDigits(hours)
        2 -> sign + javaTimeTwoDigits(hours) + javaTimeTwoDigits(minutes)
        4 -> {
            val text = sign + javaTimeTwoDigits(hours) + javaTimeTwoDigits(minutes)
            if (seconds != 0) text + javaTimeTwoDigits(seconds) else text
        }
        5 -> {
            val text = sign + javaTimeTwoDigits(hours) + ":" + javaTimeTwoDigits(minutes)
            if (seconds != 0) text + ":" + javaTimeTwoDigits(seconds) else text
        }
        else -> sign + javaTimeTwoDigits(hours) + ":" + javaTimeTwoDigits(minutes)
    }
}

private fun javaTimeFormatOffsetZ(offset: ZoneOffset, count: Int): String {
    val total = offset.totalSeconds
    val absolute = if (total < 0) -total else total
    val hours = absolute / 3_600
    val minutes = (absolute / 60) % 60
    val seconds = absolute % 60
    val sign = if (total < 0) "-" else "+"
    val text = sign + javaTimeTwoDigits(hours) + javaTimeTwoDigits(minutes)
    return if (count >= 4 && seconds != 0) text + javaTimeTwoDigits(seconds) else text
}

private fun javaTimeMonthShortName(month: Int): String = when (month) {
    1 -> "Jan"
    2 -> "Feb"
    3 -> "Mar"
    4 -> "Apr"
    5 -> "May"
    6 -> "Jun"
    7 -> "Jul"
    8 -> "Aug"
    9 -> "Sep"
    10 -> "Oct"
    11 -> "Nov"
    else -> "Dec"
}

private fun javaTimeMonthName(month: Int): String = when (month) {
    1 -> "January"
    2 -> "February"
    3 -> "March"
    4 -> "April"
    5 -> "May"
    6 -> "June"
    7 -> "July"
    8 -> "August"
    9 -> "September"
    10 -> "October"
    11 -> "November"
    else -> "December"
}
