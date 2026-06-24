#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testGetTimeMicrosLowersToRuntimeCallee() throws {
        let source = """
        import kotlin.system.getTimeMicros

        fun main(): Long = getTimeMicros()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_system_getTimeMicros"), "Expected getTimeMicros runtime call")
        }
    }

    @Test func testGetTimeMillisLowersToRuntimeCallee() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main(): Long = getTimeMillis()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_system_getTimeMillis"), "Expected getTimeMillis runtime call")
        }
    }

    @Test func testGetTimeNanosLowersToRuntimeCallee() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main(): Long = getTimeNanos()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_system_getTimeNanos"), "Expected getTimeNanos runtime call")
        }
    }

    @Test func testSystemObjectMembersLowerToRuntimeCallees() throws {
        let source = """
        import kotlin.system.System

        fun main(): Long {
            val millis = System.currentTimeMillis()
            val nanos = System.nanoTime()
            val startedAt = System.processStartNanos()
            return millis + nanos + startedAt
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_system_currentTimeMillis"), "Expected System.currentTimeMillis runtime call")
            #expect(callees.contains("kk_system_nanoTime"), "Expected System.nanoTime runtime call")
            #expect(callees.contains("kk_system_process_start_nanos"), "Expected System.processStartNanos runtime call")
        }
    }

    @Test func testMeasureTimeCallsLowerToClockDeltaRuntimeCallees() throws {
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
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.filter { $0 == "kk_system_currentTimeMillis" }.count >= 2,
                "measureTimeMillis should lower to start/end currentTimeMillis calls"
            )
            #expect(
                callees.filter { $0 == "kk_system_nanoTime" }.count >= 2,
                "measureNanoTime should lower to start/end nanoTime calls"
            )
            #expect(
                callees.filter { $0 == "kk_system_getTimeMicros" }.count >= 2,
                "measureTimeMicros should lower to start/end getTimeMicros calls"
            )
            #expect(
                callees.filter { $0 == "kk_op_sub" }.count >= 3,
                "measureTimeMillis, measureTimeMicros, and measureNanoTime should lower to elapsed-time subtraction"
            )
        }
    }

    @Test func testMeasureTimeMillisCallableReferenceRethrowsThrownResult() throws {
        let source = """
        import kotlin.system.measureTimeMillis

        fun work() {}

        fun main(): Long {
            return measureTimeMillis(::work)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let hasRethrow = body.contains { instruction in
                if case .rethrow = instruction {
                    return true
                }
                return false
            }

            #expect(
                hasRethrow,
                "measureTimeMillis callable-reference path must rethrow a non-null thrown channel"
            )
        }
    }
}
#endif
