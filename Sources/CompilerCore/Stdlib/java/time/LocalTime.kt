package java.time

import java.util.Calendar

/** A time without a date or time-zone in the ISO-8601 calendar system. */
public class LocalTime private constructor(
    public val hour: Int,
    public val minute: Int,
    public val second: Int,
    public val nano: Int,
) : Comparable<LocalTime> {
    public val minuteOfDay: Int
        get() = hour * 60 + minute

    public val secondOfDay: Int
        get() = hour * 3_600 + minute * 60 + second

    public val nanoOfDay: Long
        get() = secondOfDay.toLong() * javaTimeNanosPerSecond + nano

    public fun getHour(): Int = hour

    public fun getMinute(): Int = minute

    public fun getSecond(): Int = second

    public fun getNano(): Int = nano

    public fun toSecondOfDay(): Int = secondOfDay

    public fun toNanoOfDay(): Long = nanoOfDay

    public fun plusHours(hours: Long): LocalTime = plusNanos(javaTimeFloorMod(hours, 24L) * javaTimeNanosPerHour)

    public fun plusMinutes(minutes: Long): LocalTime = plusNanos(javaTimeFloorMod(minutes, 1_440L) * javaTimeNanosPerMinute)

    public fun plusSeconds(seconds: Long): LocalTime =
        plusNanos(javaTimeFloorMod(seconds, javaTimeSecondsPerDay) * javaTimeNanosPerSecond)

    public fun plusNanos(nanos: Long): LocalTime {
        val adjustment = javaTimeFloorMod(nanos, javaTimeNanosPerDay)
        return ofNanoOfDay(javaTimeFloorMod(nanoOfDay + adjustment, javaTimeNanosPerDay))
    }

    public fun minusHours(hours: Long): LocalTime = plusHours(-hours)

    public fun minusMinutes(minutes: Long): LocalTime = plusMinutes(-minutes)

    public fun minusSeconds(seconds: Long): LocalTime = plusSeconds(-seconds)

    public fun minusNanos(nanos: Long): LocalTime = plusNanos(-nanos)

    public fun isBefore(other: LocalTime): Boolean = compareTo(other) < 0

    public fun isAfter(other: LocalTime): Boolean = compareTo(other) > 0

    public fun format(formatter: java.time.format.DateTimeFormatter): String = formatter.format(this)

    override fun compareTo(other: LocalTime): Int {
        if (hour != other.hour) return hour.compareTo(other.hour)
        if (minute != other.minute) return minute.compareTo(other.minute)
        if (second != other.second) return second.compareTo(other.second)
        return nano.compareTo(other.nano)
    }

    override fun equals(other: Any?): Boolean =
        other is LocalTime && hour == other.hour && minute == other.minute && second == other.second && nano == other.nano

    override fun hashCode(): Int = ((hour * 60 + minute) * 60 + second) * 1_000_000_007 + nano

    override fun toString(): String {
        val builder = StringBuilder()
        builder.append(javaTimeTwoDigits(hour))
        builder.append(':')
        builder.append(javaTimeTwoDigits(minute))
        if (second != 0 || nano != 0) {
            builder.append(':')
            builder.append(javaTimeTwoDigits(second))
            if (nano != 0) {
                builder.append('.')
                val fraction: Int
                val digits: Int
                when {
                    nano % 1_000_000 == 0 -> {
                        fraction = nano / 1_000_000
                        digits = 3
                    }
                    nano % 1_000 == 0 -> {
                        fraction = nano / 1_000
                        digits = 6
                    }
                    else -> {
                        fraction = nano
                        digits = 9
                    }
                }
                val text = fraction.toString()
                builder.append("0".repeat(digits - text.length))
                builder.append(text)
            }
        }
        return builder.toString()
    }

    public companion object {
        public val MIDNIGHT: LocalTime = LocalTime(0, 0, 0, 0)
        public val NOON: LocalTime = LocalTime(12, 0, 0, 0)
        public val MIN: LocalTime = MIDNIGHT
        public val MAX: LocalTime = LocalTime(23, 59, 59, 999_999_999)

        public fun now(): LocalTime {
            val calendar = Calendar.getInstance()
            return of(
                calendar.get(Calendar.HOUR_OF_DAY),
                calendar.get(Calendar.MINUTE),
                calendar.get(Calendar.SECOND),
                calendar.get(Calendar.MILLISECOND) * 1_000_000
            )
        }

        public fun of(hour: Int, minute: Int): LocalTime = of(hour, minute, 0, 0)

        public fun of(hour: Int, minute: Int, second: Int): LocalTime = of(hour, minute, second, 0)

        public fun of(hour: Int, minute: Int, second: Int, nanoOfSecond: Int): LocalTime {
            if (hour < 0 || hour > 23) throw DateTimeException("Invalid value for HourOfDay: " + hour)
            if (minute < 0 || minute > 59) throw DateTimeException("Invalid value for MinuteOfHour: " + minute)
            if (second < 0 || second > 59) throw DateTimeException("Invalid value for SecondOfMinute: " + second)
            if (nanoOfSecond < 0 || nanoOfSecond > 999_999_999) {
                throw DateTimeException("Invalid value for NanoOfSecond: " + nanoOfSecond)
            }
            if (minute == 0 && second == 0 && nanoOfSecond == 0) {
                if (hour == 0) return MIDNIGHT
                if (hour == 12) return NOON
            }
            return LocalTime(hour, minute, second, nanoOfSecond)
        }

        public fun ofSecondOfDay(secondOfDay: Long): LocalTime {
            if (secondOfDay < 0L || secondOfDay >= javaTimeSecondsPerDay) {
                throw DateTimeException("Invalid value for SecondOfDay: " + secondOfDay)
            }
            val hour = (secondOfDay / 3_600L).toInt()
            val minute = ((secondOfDay % 3_600L) / 60L).toInt()
            val second = (secondOfDay % 60L).toInt()
            return of(hour, minute, second)
        }

        public fun ofNanoOfDay(nanoOfDay: Long): LocalTime {
            if (nanoOfDay < 0L || nanoOfDay >= javaTimeNanosPerDay) {
                throw DateTimeException("Invalid value for NanoOfDay: " + nanoOfDay)
            }
            val secondOfDay = nanoOfDay / javaTimeNanosPerSecond
            val nano = (nanoOfDay % javaTimeNanosPerSecond).toInt()
            val time = ofSecondOfDay(secondOfDay)
            return of(time.hour, time.minute, time.second, nano)
        }

        public fun parse(text: CharSequence): LocalTime {
            val value = text.toString()
            if (value.length < 5 || value[2] != ':') {
                throw DateTimeException("Invalid ISO time: " + value)
            }
            try {
                val hour = value.substring(0, 2).toInt()
                val minute = value.substring(3, 5).toInt()
                if (value.length == 5) return of(hour, minute)
                if (value[5] != ':' || value.length < 8) throw DateTimeException("Invalid ISO time: " + value)
                val second = value.substring(6, 8).toInt()
                if (value.length == 8) return of(hour, minute, second)
                if (value[8] != '.') throw DateTimeException("Invalid ISO time: " + value)
                val fraction = value.substring(9)
                if (fraction.length < 1 || fraction.length > 9) throw DateTimeException("Invalid ISO time: " + value)
                val nano = (fraction + "000000000").substring(0, 9).toInt()
                return of(hour, minute, second, nano)
            } catch (error: NumberFormatException) {
                throw DateTimeException("Invalid ISO time: " + value)
            }
        }
    }
}
