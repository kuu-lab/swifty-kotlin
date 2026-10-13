#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test func testSystemObjectMembersLowerToBundledKotlinCallees() throws {
        let source = """
        import kotlin.system.System

        fun main(): Long {
            val millis = System.currentTimeMillis()
            val nanos = System.nanoTime()
            val startedAt = System.processStartNanos()
            return millis + nanos + startedAt
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("currentTimeMillis"), "Expected System.currentTimeMillis bundled call")
        #expect(callees.contains("nanoTime"), "Expected System.nanoTime bundled call")
        #expect(
            callees.contains("processStartNanos"),
            "Expected System.processStartNanos bundled call"
        )
        for bridge in [
            runtimeCallee(.systemCurrentTimeMillis),
            runtimeCallee(.systemNanoTime),
            runtimeCallee(.systemProcessStartNanos),
        ] {
            #expect(!callees.contains(bridge), "User KIR must not call \(bridge) directly")
        }
    }

    /// KSP-617: measureTime* are bundled Kotlin inline functions, no longer a
    /// KIR special case expanding to paired clock reads.
    @Test func testMeasureTimeCallsLowerToBundledKotlinCallees() throws {
        let source = """
        import kotlin.system.measureNanoTime
        import kotlin.system.measureTimeMicros
        import kotlin.system.measureTimeMillis

        fun main(): Long {
            val millis = measureTimeMillis { }
            val micros = measureTimeMicros { }
            val nanos = measureNanoTime { }
            return millis + micros + nanos
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        for callee in ["measureTimeMillis", "measureTimeMicros", "measureNanoTime"] {
            #expect(callees.contains(callee), "Expected a call to the bundled \(callee)")
        }
        for bridge in [
            runtimeCallee(.systemCurrentTimeMillis), runtimeCallee(.systemGetTimeMicros), runtimeCallee(.systemGetTimeNanos),
        ] {
            #expect(!callees.contains(bridge), "\(bridge) must not be inlined into user KIR")
        }
    }

    @Test func testMeasureTimeMillisAcceptsCallableReferenceBlock() throws {
        let source = """
        import kotlin.system.measureTimeMillis

        fun work() {}

        fun main(): Long {
            return measureTimeMillis(::work)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "measureTimeMillis(::work) must type-check")

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("measureTimeMillis"))
        #expect(
            callees.contains(runtimeCallee(.callableRefTagKfunction)),
            "The callable reference must be materialised before the call"
        )
    }
}
#endif
