import java.time.*
import java.time.format.DateTimeFormatter

fun main() {
    val date = LocalDate.of(2020, 1, 1)
    val time = LocalTime.of(1, 2)
    val dateTime = LocalDateTime.of(2020, 1, 1, 0, 0)

    println(date)
    println(time)
    println(dateTime)
    println(Period.ofDays(1))
    println(Duration.ofSeconds(5))
    println(Instant.ofEpochMilli(1234))
    println(Instant.now().toEpochMilli() > 0L)
    println(DateTimeFormatter.ISO_DATE.format(date))
    println(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").format(dateTime))
    println(LocalDate.of(2020, 1, 31).plusMonths(1))
    println(LocalDate.parse("2020-02-29").dayOfWeek)
}
