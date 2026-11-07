package java.text

import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.internal.KsSymbolName
import kotlin.math.abs

public class SimpleDateFormat(
    private var pattern: String,
    private val symbolsLocale: Locale,
) {
    private val symbols = DateFormatSymbols(symbolsLocale)

    public constructor() : this(defaultPattern(Locale.getDefault()), Locale.getDefault())

    public constructor(pattern: String) : this(pattern, Locale.getDefault())

    init {
        validatePattern(pattern)
    }

    public fun parse(source: String): Date = Date(__kkSimpleDateFormatParse(pattern, source))

    public fun applyPattern(value: String) {
        validatePattern(value)
        pattern = value
    }

    public fun toPattern(): String = pattern

    public fun format(date: Date): String {
        val calendar = Calendar.getInstance()
        calendar.time = date
        val out = StringBuilder()
        var i = 0
        val n = pattern.length
        while (i < n) {
            val c = pattern[i]
            when {
                c == '\'' -> {
                    if (i + 1 < n && pattern[i + 1] == '\'') {
                        out.append('\'')
                        i += 2
                    } else {
                        val close = pattern.indexOf('\'', i + 1)
                        if (close < 0) {
                            out.append(pattern, i + 1, n)
                            i = n
                        } else {
                            out.append(pattern, i + 1, close)
                            i = close + 1
                        }
                    }
                }
                c.isLetter() -> {
                    var j = i + 1
                    while (j < n && pattern[j] == c) j++
                    appendField(c, j - i, calendar, out)
                    i = j
                }
                else -> {
                    out.append(c)
                    i++
                }
            }
        }
        return out.toString()
    }

    private fun appendField(letter: Char, count: Int, calendar: Calendar, out: StringBuilder) {
        when (letter) {
            'y' -> appendYear(calendar[Calendar.YEAR], count, out)
            'Y' -> {
                val year = calendar[Calendar.YEAR]
                val weekYear = if (calendar[Calendar.MONTH] == 11 && calendar[Calendar.WEEK_OF_YEAR] == 1) {
                    year + 1
                } else {
                    year
                }
                appendYear(weekYear, count, out)
            }
            'M', 'L' -> when {
                count <= 2 -> out.append((calendar[Calendar.MONTH] + 1).toString().padStart(count, '0'))
                count == 3 -> out.append(symbols.shortMonths[calendar[Calendar.MONTH]])
                count == 4 -> out.append(symbols.months[calendar[Calendar.MONTH]])
                else -> appendNarrowMonth(calendar[Calendar.MONTH], out)
            }
            'd' -> out.append(calendar[Calendar.DATE].toString().padStart(count, '0'))
            'D' -> out.append(calendar[Calendar.DAY_OF_YEAR].toString().padStart(count, '0'))
            'F' -> out.append(calendar[Calendar.DAY_OF_WEEK_IN_MONTH].toString().padStart(count, '0'))
            'w' -> out.append(calendar[Calendar.WEEK_OF_YEAR].toString().padStart(count, '0'))
            'W' -> out.append(calendar[Calendar.WEEK_OF_MONTH].toString().padStart(count, '0'))
            'E' -> when {
                count == 4 -> out.append(symbols.weekdays[calendar[Calendar.DAY_OF_WEEK]])
                count >= 5 -> appendNarrowWeekday(calendar[Calendar.DAY_OF_WEEK], out)
                else -> out.append(symbols.shortWeekdays[calendar[Calendar.DAY_OF_WEEK]])
            }
            'u' -> out.append(isoDayOfWeek(calendar).toString().padStart(count, '0'))
            'a' -> out.append(symbols.amPmStrings[calendar[Calendar.AM_PM]])
            'G' -> out.append(symbols.eras[calendar[Calendar.ERA]])
            'h' -> out.append((((calendar[Calendar.HOUR_OF_DAY] + 11) % 12) + 1).toString().padStart(count, '0'))
            'H' -> out.append(calendar[Calendar.HOUR_OF_DAY].toString().padStart(count, '0'))
            'K' -> out.append(calendar[Calendar.HOUR].toString().padStart(count, '0'))
            'k' -> {
                val h = calendar[Calendar.HOUR_OF_DAY]
                out.append((if (h == 0) 24 else h).toString().padStart(count, '0'))
            }
            'm' -> out.append(calendar[Calendar.MINUTE].toString().padStart(count, '0'))
            's' -> out.append(calendar[Calendar.SECOND].toString().padStart(count, '0'))
            'S' -> out.append(calendar[Calendar.MILLISECOND].toString().padStart(count, '0'))
            'z' -> {
                val tz = calendar.timeZone
                val style = if (count >= 4) java.util.TimeZone.LONG else java.util.TimeZone.SHORT
                out.append(tz.getDisplayName(tz.inDaylightTime(calendar.time), style, symbolsLocale))
            }
            'Z' -> out.append(formatOffset(calendar, withColon = false, hoursOnly = false))
            'X' -> out.append(formatIsoOffset(calendar, count))
            else -> repeat(count) { out.append(letter) }
        }
    }

    private fun appendYear(year: Int, count: Int, out: StringBuilder) {
        if (count == 2) {
            out.append((year % 100).toString().padStart(2, '0'))
        } else {
            out.append(year.toString().padStart(count, '0'))
        }
    }

    private fun isoDayOfWeek(calendar: Calendar): Int {
        val dow = calendar[Calendar.DAY_OF_WEEK]
        return if (dow == 1) 7 else dow - 1
    }

    private fun appendNarrowMonth(month: Int, out: StringBuilder) {
        if (symbolsLocale.language == "ja") {
            out.append((month + 1).toString()).append('月')
        } else {
            out.append(symbols.shortMonths[month].first())
        }
    }

    private fun appendNarrowWeekday(dayOfWeek: Int, out: StringBuilder) {
        if (symbolsLocale.language == "ja") {
            out.append(symbols.weekdays[dayOfWeek])
        } else {
            out.append(symbols.shortWeekdays[dayOfWeek].first())
        }
    }

    private fun zoneOffsetMinutes(calendar: Calendar): Int {
        return calendar.timeZone.getOffset(calendar.timeInMillis) / 60_000
    }

    private fun formatOffset(calendar: Calendar, withColon: Boolean, hoursOnly: Boolean): String {
        val total = zoneOffsetMinutes(calendar)
        val sign = if (total < 0) '-' else '+'
        val absMinutes = abs(total)
        val hours = (absMinutes / 60).toString().padStart(2, '0')
        if (hoursOnly) return "$sign$hours"
        val minutes = (absMinutes % 60).toString().padStart(2, '0')
        return if (withColon) "$sign$hours:$minutes" else "$sign$hours$minutes"
    }

    private fun formatIsoOffset(calendar: Calendar, count: Int): String {
        val total = zoneOffsetMinutes(calendar)
        if (total == 0) return "Z"
        return when (count) {
            1 -> formatOffset(calendar, withColon = false, hoursOnly = true)
            2 -> formatOffset(calendar, withColon = false, hoursOnly = false)
            else -> formatOffset(calendar, withColon = true, hoursOnly = false)
        }
    }

    private companion object {
        const val VALID_PATTERN_LETTERS = "adhkmsuwyzDEFGHKLMSWXYZ"

        fun defaultPattern(locale: Locale): String =
            if (locale.language == "ja") "yy/MM/dd" else "M/d/yy"

        fun validatePattern(pattern: String) {
            var i = 0
            val n = pattern.length
            while (i < n) {
                val c = pattern[i]
                when {
                    c == '\'' -> {
                        if (i + 1 < n && pattern[i + 1] == '\'') {
                            i += 2
                        } else {
                            val close = pattern.indexOf('\'', i + 1)
                            i = if (close < 0) n else close + 1
                        }
                    }
                    c.isLetter() -> {
                        var j = i + 1
                        while (j < n && pattern[j] == c) j++
                        if (c !in VALID_PATTERN_LETTERS) {
                            throw IllegalArgumentException("Illegal pattern character '$c'")
                        }
                        if (c == 'X' && j - i > 3) {
                            throw IllegalArgumentException("invalid ISO 8601 format: length=${j - i}")
                        }
                        i = j
                    }
                    else -> i++
                }
            }
        }
    }
}

@KsSymbolName("__kk_simple_date_format_parse")
private external fun __kkSimpleDateFormatParse(pattern: String, source: String): Long
