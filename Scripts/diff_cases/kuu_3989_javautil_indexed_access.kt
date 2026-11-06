// KUU-3989: bundled java.* get/set members must carry `operator` so the JVM
// indexed-access conventions resolve — bs[i], bs[i] = v, bs[i, j],
// bs[i, j] = v on java.util.BitSet, cal[field] = value on java.util.Calendar,
// and future[timeout, unit] on java.util.concurrent.Future.
import java.util.BitSet
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.concurrent.Callable
import java.util.concurrent.CompletableFuture
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

fun main() {
    val bs = BitSet(8)
    bs[0] = true
    bs[2] = true
    bs[2] = false
    println("${bs[0]} ${bs[1]} ${bs[2]}")

    // bs[i, j] reads through get(fromIndex, toIndex) -> BitSet.
    val sub = bs[0, 3]
    println(sub.cardinality())
    println(sub[0])

    // bs[i, j] = v writes through set(fromIndex, toIndex, value).
    bs[1, 4] = true
    println(bs.cardinality())
    bs[1, 4] = false
    println(bs.cardinality())

    // bs[i] = intValue binds set(fromIndex, toIndex) — the JVM range-set quirk.
    val ranged = BitSet(16)
    ranged[2] = 5
    println(ranged.cardinality())
    println("${ranged[2]} ${ranged[3]} ${ranged[4]} ${ranged[5]}")

    // Explicit calls keep working next to the operator forms.
    ranged.set(9)
    println(ranged[9])
    ranged.set(9, false)
    println(ranged[9])

    // java.util.Calendar field indexed access.
    val cal = GregorianCalendar(2024, 0, 15)
    cal[Calendar.MONTH] = 5
    println(cal[Calendar.MONTH])
    println(cal[Calendar.YEAR])

    // java.util.concurrent.Future.get(timeout, unit) via f[t, u].
    val task = FutureTask(Callable<Int> { 42 })
    task.run()
    println(task[5L, TimeUnit.SECONDS])

    val cf = CompletableFuture<Int>()
    cf.complete(7)
    println(cf[5L, TimeUnit.SECONDS])
}
