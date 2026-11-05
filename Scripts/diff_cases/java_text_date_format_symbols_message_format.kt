// KUU-4004: bundled java.text.DateFormatSymbols / MessageFormat.
// Covers the Rosetta Calendar usage:
//   DateFormatSymbols(locale).shortWeekdays / .months
//   MessageFormat.format("%{0}s%{1}s", len, 21 - len)
import java.text.DateFormatSymbols
import java.text.MessageFormat
import java.util.Date
import java.util.Locale

fun main() {
    val us = DateFormatSymbols(Locale.US)
    println(us.eras.joinToString("|"))
    println(us.months.joinToString("|"))
    println(us.shortMonths.joinToString("|"))
    println(us.weekdays.joinToString("|"))
    println(us.shortWeekdays.joinToString("|"))
    println(us.amPmStrings.joinToString("|"))
    println("${us.months.size}/${us.weekdays.size}/${us.eras.size}")

    // Rosetta Calendar slices: shortWeekdays[1..7], months[0..11]
    println(us.shortWeekdays.slice(1..7).joinToString(","))
    println(us.months.slice(0..11).joinToString(","))

    val ja = DateFormatSymbols(Locale.JAPANESE)
    println(ja.eras.joinToString("|"))
    println(ja.months.joinToString("|"))
    println(ja.weekdays.joinToString("|"))
    println(ja.shortWeekdays.joinToString("|"))
    println(ja.amPmStrings.joinToString("|"))

    val de = DateFormatSymbols(Locale.GERMANY)
    println(de.eras.joinToString("|"))
    println(de.shortMonths.joinToString("|"))
    println(de.shortWeekdays.joinToString("|"))

    // Constructor without arguments uses the default locale on both stacks.
    println(DateFormatSymbols().eras.joinToString("|"))
    println(DateFormatSymbols.getInstance(Locale.FRANCE).months[0])

    // Setter/getter round-trip.
    us.months = arrayOf("M1", "M2")
    println(us.getMonths().joinToString("|"))

    // Plain argument substitution.
    println(MessageFormat.format("Hello {0}, you are {1} years old", "World", 42))
    println(MessageFormat.format("{0} {0} {1}", "x", "y"))
    println(MessageFormat.format("missing {1}", "only"))
    println(MessageFormat.format("null {0} end", null))

    // Rosetta Calendar pattern: %{0}s%{1}s -> %15s%6s for String.format.
    val len = 9
    println(MessageFormat.format("%{0}s%{1}s", len, 21 - len))

    // Number formatting.
    println(MessageFormat.format("{0}", 1234567))
    println(MessageFormat.format("{0}", 3.1428))
    println(MessageFormat.format("{0,number}", 1234567.891))
    println(MessageFormat.format("{0,number,integer}", 1234.5))
    println(MessageFormat.format("{0,number,percent}", 0.25))
    println(MessageFormat.format("{0,number,currency}", 12.5))
    println(MessageFormat.format("{0,number,0.00}", 3.14159))
    println(MessageFormat.format("{0,number,#,##0.0}", -9876.5))

    // Locale-aware number formatting.
    println(MessageFormat("{0,number}", Locale.GERMANY).format(arrayOf(1234567.891)))
    println(MessageFormat("{0,number,percent}", Locale.FRANCE).format(arrayOf(0.25)))

    // Choice formatting, including a nested argument in the selected message.
    println(MessageFormat.format("{0,choice,0#zero|1#one|2#two}", 1))
    println(MessageFormat.format("{0,choice,0#zero|1#one|2#two}", 5))
    println(MessageFormat.format("{0,choice,0#zero {1}|1#one {1}}", 0, "x"))

    // Date/time formatting for the default (en-US) locale.
    println(MessageFormat.format("{0,date}", Date(0L)))
    println(MessageFormat.format("{0,time,short}", Date(0L)))
    println(MessageFormat.format("{0,date,yyyy-MM-dd}", Date(0L)))
}
