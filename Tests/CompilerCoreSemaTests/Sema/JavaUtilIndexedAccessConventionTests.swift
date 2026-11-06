@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// KUU-3989: bundled java.* `get`/`set` members must carry `operator` so the
/// JVM indexed-access conventions resolve — `bs[i] = v`, `bs[i, j]`,
/// `cal[field] = value`, `future[timeout, unit]`. Runtime behaviour is
/// pinned by the `kuu_3989_javautil_indexed_access` diff case; these tests
/// pin the compile-time surface (the KSWIFTK-SEMA-0432 diagnostics the
/// ticket reported).
@Suite
struct JavaUtilIndexedAccessConventionTests {
    @Test
    func javaUtilBitSetIndexedAccessCompiles() throws {
        let context = makeContextFromSource("""
        import java.util.BitSet

        fun probe() {
            val bs = BitSet(8)
            bs[0] = true
            bs[2] = true
            bs[2] = false
            val bit: Boolean = bs[0]
            val sub = bs[0, 3]
            bs[1, 4] = true
            bs[1, 4] = false
            val ranged = BitSet(16)
            ranged[2] = 5
            ranged.set(9)
            ranged.set(9, false)
        }
        """)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func javaUtilCalendarFieldIndexedAccessCompiles() throws {
        let context = makeContextFromSource("""
        import java.util.Calendar
        import java.util.GregorianCalendar

        fun probe() {
            val cal = GregorianCalendar(2024, 0, 15)
            cal[Calendar.MONTH] = 5
            val month: Int = cal[Calendar.MONTH]
            cal[Calendar.YEAR] = 2025
        }
        """)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func javaUtilFutureTimeoutIndexedAccessCompiles() throws {
        let context = makeContextFromSource("""
        import java.util.concurrent.Callable
        import java.util.concurrent.CompletableFuture
        import java.util.concurrent.FutureTask
        import java.util.concurrent.TimeUnit

        fun probe() {
            val task = FutureTask(Callable<Int> { 42 })
            val value: Int = task[5L, TimeUnit.SECONDS]
            val cf = CompletableFuture<Int>()
            val other: Int = cf[5L, TimeUnit.SECONDS]
        }
        """)
        do { try runSema(context) } catch {}
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }
}
