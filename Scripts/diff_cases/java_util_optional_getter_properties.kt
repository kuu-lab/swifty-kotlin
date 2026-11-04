import java.util.BitSet
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.Locale
import java.util.Optional
import java.util.OptionalDouble
import java.util.OptionalInt
import java.util.OptionalLong
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentSkipListMap
import java.util.concurrent.ConcurrentSkipListSet
import java.util.zip.CRC32

fun main() {
    // KUU-4047: Java `is`-getter convention — `opt.isPresent` and
    // `opt.isPresent()` are both valid on the JVM.
    val o = Optional.of(5)
    println(o.isPresent)
    println(o.isEmpty)
    println(o.isPresent())
    println(o.isEmpty())
    println(Optional.empty<Int>().isPresent)
    println(Optional.empty<Int>().isEmpty)
    val oi = OptionalInt.of(3)
    println(oi.isPresent)
    println(oi.isEmpty)
    val ol = OptionalLong.of(7L)
    println(ol.isPresent)
    val od = OptionalDouble.of(1.5)
    println(od.isEmpty)
    println(BitSet().isEmpty)
    Optional.of(1).run { println(isPresent) }

    // KUU-3988: `getValue()` is a Java `get`-getter -> `.value` property.
    val crc = CRC32()
    crc.update("ab".toByteArray())
    println(crc.value)
    println(crc.getValue())

    // misc java.util gaps from the same ticket.
    val u = UUID.fromString("01020304-0506-0708-090a-0b0c0d0e0f10")
    println(u.mostSignificantBits)
    println(u.getMostSignificantBits())
    println(u.leastSignificantBits)
    println(UUID.nameUUIDFromBytes("name".toByteArray()).version())

    println(Locale.US.displayName.isNotEmpty())
    println(Locale.US.displayLanguage.isNotEmpty())
    println(Locale.US.displayCountry.isNotEmpty())

    println(TimeZone.getTimeZone("UTC").useDaylightTime())
    println(TimeZone.getTimeZone("America/New_York").useDaylightTime())

    println(Calendar.JANUARY)
    println(Calendar.DECEMBER)
    println(Calendar.UNDECIMBER)
    println(Calendar.SUNDAY)
    println(Calendar.SATURDAY)
    println(Calendar.AM)
    println(Calendar.PM)

    println(GregorianCalendar().isLeapYear(2024))
    println(GregorianCalendar().isLeapYear(1900))
    println(GregorianCalendar.AD)
    println(GregorianCalendar.BC)

    val q = ArrayBlockingQueue<Int>(2)
    println(q.offer(1))
    println(q.offer(2))
    println(q.offer(3))
    println(q.poll())
    println(q.remainingCapacity())

    val skipSet = ConcurrentSkipListSet<Int>()
    skipSet.add(2)
    skipSet.add(1)
    println(skipSet.size)
    val skipMap = ConcurrentSkipListMap<Int, String>()
    skipMap[1] = "a"
    println(skipMap[1])
}
