import java.time.*
import java.time.format.DateTimeFormatter

fun main() {
    // LocalDate.format (KUU-4033)
    val date = LocalDate.of(2024, 1, 15)
    println(date.format(DateTimeFormatter.ISO_DATE))
    println(date.format(DateTimeFormatter.ofPattern("yyyy/MM/dd")))

    // ZoneOffset factories and ids
    println(ZoneOffset.UTC)
    println(ZoneOffset.UTC.id)
    println(ZoneOffset.of("+02:00"))
    println(ZoneOffset.of("-05:30"))
    println(ZoneOffset.of("Z"))
    println(ZoneOffset.of("+9"))
    println(ZoneOffset.of("+0930"))
    println(ZoneOffset.of("+09:30:45"))
    println(ZoneOffset.ofHours(9))
    println(ZoneOffset.ofHours(-3))
    println(ZoneOffset.ofHoursMinutes(5, 45))
    println(ZoneOffset.ofHoursMinutesSeconds(5, 45, 30))
    println(ZoneOffset.ofHoursMinutesSeconds(0, -30, 0))
    println(ZoneOffset.ofHoursMinutes(-9, -30))
    println(ZoneOffset.ofTotalSeconds(3600))
    println(ZoneOffset.ofTotalSeconds(-3661))
    println(ZoneOffset.ofTotalSeconds(64800))
    println(ZoneOffset.MIN)
    println(ZoneOffset.MAX)
    println(ZoneOffset.ofHours(9).totalSeconds)
    println(ZoneOffset.ofHours(9).id)
    println(ZoneOffset.of("+18:00"))
    println(ZoneOffset.of("-18:00"))
    println(ZoneOffset.ofHours(9).compareTo(ZoneOffset.UTC))
    println(ZoneOffset.ofHours(9) == ZoneOffset.ofTotalSeconds(32400))
    println(ZoneOffset.ofHours(9).hashCode())
    try { ZoneOffset.of("+19:00") } catch (e: DateTimeException) { println("ex1: " + e.message) }
    try { ZoneOffset.of("garbage") } catch (e: DateTimeException) { println("ex2: " + e.message) }
    try { ZoneOffset.ofHours(19) } catch (e: DateTimeException) { println("ex3: " + e.message) }
    try { ZoneOffset.ofHoursMinutes(9, 60) } catch (e: DateTimeException) { println("ex4: " + e.message) }
    try { ZoneOffset.ofHoursMinutes(9, -30) } catch (e: DateTimeException) { println("ex5: " + e.message) }
    try { ZoneOffset.of("+18:01") } catch (e: DateTimeException) { println("ex6: " + e.message) }
    try { ZoneOffset.of("+9:00") } catch (e: DateTimeException) { println("ex7: " + e.message) }
    try { ZoneOffset.ofTotalSeconds(64801) } catch (e: DateTimeException) { println("ex8: " + e.message) }

    // ZoneId
    println(ZoneId.of("Z") === ZoneOffset.UTC)
    println(ZoneId.of("+09:00") == ZoneOffset.ofHours(9))
    println(ZoneId.of("+09:00") is ZoneOffset)
    println(ZoneId.of("UTC"))
    println(ZoneId.of("GMT+09:00"))
    println(ZoneId.of("UTC").normalized())
    println(ZoneId.systemDefault() is ZoneId)
    println(ZoneId.ofOffset("", ZoneOffset.ofHours(2)))
    println(ZoneId.ofOffset("UTC", ZoneOffset.UTC))
    try { ZoneId.of("Bogus/Zone") } catch (e: DateTimeException) { println("zone-ex: " + e.message) }

    // OffsetDateTime
    val odt = OffsetDateTime.of(2024, 1, 15, 10, 30, 45, 123456789, ZoneOffset.ofHours(9))
    println(odt)
    println(odt.offset)
    println(odt.toLocalDateTime())
    println(odt.toLocalDate())
    println(odt.toLocalTime())
    println(odt.toInstant())
    println(odt.toEpochSecond())
    println("" + odt.year + "/" + odt.monthValue + "/" + odt.dayOfMonth + " " + odt.hour + ":" + odt.minute + ":" + odt.second + "." + odt.nano)
    println(odt.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME))
    println(odt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")))
    println(odt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX")))
    println(OffsetDateTime.of(LocalDateTime.of(2024, 1, 15, 10, 30), ZoneOffset.UTC))
    println(OffsetDateTime.of(LocalDate.of(2024, 2, 29), LocalTime.of(23, 59, 59), ZoneOffset.ofHours(-5)))
    println(OffsetDateTime.ofInstant(Instant.ofEpochSecond(1705316445L, 123456789L), ZoneOffset.UTC))
    println(OffsetDateTime.ofInstant(Instant.ofEpochSecond(1705316445L), ZoneOffset.ofHours(9)))
    println(OffsetDateTime.parse("2024-01-15T10:30:45+09:00"))
    println(OffsetDateTime.parse("2024-01-15T10:30:45.123456789Z"))
    println(OffsetDateTime.parse("2024-01-15T10:30:45-05:30"))
    val a = OffsetDateTime.of(2024, 1, 15, 10, 0, 0, 0, ZoneOffset.UTC)
    val b = OffsetDateTime.of(2024, 1, 15, 19, 0, 0, 0, ZoneOffset.ofHours(9))
    println("cmp=" + a.compareTo(b) + " eq=" + (a == b) + " isEqual=" + a.isEqual(b))
    println("before/after=" + a.isBefore(b) + "/" + a.isAfter(b))
    println(b.withOffsetSameInstant(ZoneOffset.UTC))
    println(b.withOffsetSameLocal(ZoneOffset.UTC))
    // LocalDateTime.plus* must carry the wrapped day into the date
    println(LocalDateTime.of(2024, 1, 15, 19, 0).plusSeconds(-32400))
    println(LocalDateTime.of(2024, 1, 15, 23, 30).plusHours(2))
    println(LocalDateTime.of(2024, 1, 15, 23, 59).plusMinutes(90))
    println(LocalDateTime.of(2024, 1, 15, 0, 30).plusMinutes(-90))
    println(odt.plusDays(1))
    println(odt.plusHours(3))
    println(odt.minusDays(1))
    println(OffsetDateTime.MIN)
    println(OffsetDateTime.MAX)
    println(OffsetDateTime.now(ZoneOffset.UTC).offset)
    println(OffsetDateTime.now(ZoneOffset.ofHours(9)).offset)
    println(LocalDateTime.of(2024, 1, 15, 10, 30).atOffset(ZoneOffset.ofHours(1)))
    println(Instant.ofEpochSecond(1705316445L).atOffset(ZoneOffset.UTC))
    println(OffsetDateTime.timeLineOrder().compare(a, b))
}
