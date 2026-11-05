// KUU-3922: kotlinx-datetime's deprecated-ctor-compat pattern — a
// @kotlin.internal.LowPriorityInOverloadResolution top-level function legally
// shares its signature with the class constructor (kotlinc accepts; KSwiftK
// used to reject the pair with SEMA-0001). Calls must prefer the regular
// constructor; calls using the compat function's own parameter names still
// reach it.
// DIFF_JVM: KUU-4286 — the JVM lane resolves the annotation through the
// bundled stdlib declarations and must keep the same overload ordering.
class LocalDate(val year: Int, val month: Int, val day: Int)

@Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@kotlin.internal.LowPriorityInOverloadResolution
fun LocalDate(year: Int, monthNumber: Int, dayOfMonth: Int): LocalDate =
    LocalDate(year = year, month = monthNumber, day = dayOfMonth)

fun main() {
    // Positional and constructor-shaped calls bind the constructor.
    println(LocalDate(2020, 1, 1).year)
    println(LocalDate(year = 2021, month = 2, day = 3).year)
    // Compat-only parameter names still reach the deprecated function.
    println(LocalDate(year = 2022, monthNumber = 6, dayOfMonth = 15).year)
}
