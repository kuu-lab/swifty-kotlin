#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4330: Map members admitted by the synthetic collection fallback
/// (`containsKey`/`containsValue`/`getValue`/`getOrDefault`/`getOrElse`/
/// `getOrPut`) bound without checking arguments against their real `K`/`V`
/// parameter signatures, so calls like `map.containsValue(2..4)` compiled
/// even though kotlinc rejects them. These tests pin the kotlinc-parity
/// rejections and the still-valid calls (verified against kotlinc:
/// `getOrDefault(1, 2)` infers `V = Any`, and `putAll` has an
/// `Iterable<Pair>` overload).
@Suite
struct MapFallbackArgumentConformanceTests {
    @Test
    func mismatchedKeyAndValueArgumentsAreRejected() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val map = mutableMapOf(1 to "a", 2 to "b")
            println(map.contains(2..4))
            println(map.containsKey("x"))
            println(map.containsValue(2..4))
            println(map.containsValue(1))
            println(map.getValue(2..4))
            println(map.getValue("x"))
            println(map.getOrElse(2..4) { "d" })
            println(map.getOrElse("x") { "d" })
            println(map.getOrDefault(2..4, "x"))
            println(map.getOrDefault("x", "y"))
            println(map.getOrPut(2..4) { "d" })
            println(map.putAll("x"))
            println(map.plus("x"))
            println(map.plus(1))
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 14, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func conformingKeyValueAndCollectionArgumentsStillResolve() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val map = mutableMapOf(1 to "a", 2 to "b")
            val longMap = mutableMapOf(1L to "a")
            println(map.contains(1))
            println(map.containsKey(2))
            println(map.containsValue("a"))
            println(map.getValue(1))
            println(map.getValue(2))
            println(longMap.getValue(1))
            println(map.getOrElse(1) { "d" })
            println(map.getOrElse(3) { "d" })
            println(map.getOrDefault(1, "x"))
            println(map.getOrDefault(3, "x"))
            println(map.getOrPut(3) { "c" })
            println(map.putAll(mapOf(3 to "c")))
            println(map.putAll(mutableMapOf(4 to "d")))
            println(map.putAll(listOf(5 to "e")))
            println(map.plus(3 to "c"))
            println(map.plus(mapOf(3 to "c")))
            println(map.plus(listOf(3 to "c")))
            println(map.plus(sequenceOf(3 to "c")))
            println(map.minus(1))
            println(map.minus(listOf(1)))
            println(map.minus(arrayOf(1)))
            println(map.minus(sequenceOf(1)))
            println(map.getOrElse(key = 1) { "d" })
            println(map.getOrDefault(defaultValue = "x", key = 1))
            val fallback: () -> String = { "f" }
            println(map.getOrElse(1, fallback))
            // kotlinc accepts these: V/K widen to Any through inference.
            println(map.getOrDefault(1, 2))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
