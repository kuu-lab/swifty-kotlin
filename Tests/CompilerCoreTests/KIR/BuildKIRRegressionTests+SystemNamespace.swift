#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testSystemNamespaceRuntimeCallees() throws {
        let sources = [
            """
            package sample0
            import kotlin.system.getTimeMicros

            fun main0(): Long = getTimeMicros()
            """,
            """
            package sample1
            import kotlin.system.getTimeMillis

            fun main1(): Long = getTimeMillis()
            """,
            """
            package sample2
            import kotlin.system.getTimeNanos

            fun main2(): Long = getTimeNanos()
            """,
            """
            package sample3
            import kotlin.system.System

            fun main3(): Long {
                val millis = System.currentTimeMillis()
                val nanos = System.nanoTime()
                val startedAt = System.processStartNanos()
                return millis + nanos + startedAt
            }
            """,
            """
            package sample4
            import kotlin.system.measureNanoTime
            import kotlin.system.measureTimeMicros
            import kotlin.system.measureTimeMillis

            fun main4(): Long {
                val millis = measureTimeMillis { }
                val micros = measureTimeMicros { }
                val nanos = measureNanoTime { }
                return millis + micros + nanos
            }
            """,
            """
            package sample5
            import kotlin.system.measureTimeMillis

            fun work5() {}

            fun main5(): Long {
                return measureTimeMillis(::work5)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main0", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_system_getTimeMicros"), "Expected getTimeMicros runtime call")
            }

            do {
                let body = try findKIRFunctionBody(named: "main1", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_system_getTimeMillis"), "Expected getTimeMillis runtime call")
            }

            do {
                let body = try findKIRFunctionBody(named: "main2", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_system_getTimeNanos"), "Expected getTimeNanos runtime call")
            }

            do {
                let body = try findKIRFunctionBody(named: "main3", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_system_currentTimeMillis"), "Expected System.currentTimeMillis runtime call")
                #expect(callees.contains("kk_system_nanoTime"), "Expected System.nanoTime runtime call")
                #expect(callees.contains("kk_system_process_start_nanos"), "Expected System.processStartNanos runtime call")
            }

            do {
                let body = try findKIRFunctionBody(named: "main4", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
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

            do {
                let body = try findKIRFunctionBody(named: "main5", in: module, interner: interner)
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
}
#endif
