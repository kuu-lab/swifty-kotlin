@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AtomicScalarApiSurfaceTests {
    @Test
    func canonicalScalarsRejectJavaMethodNames() throws {
        let arithmeticCalls = [
            "getAndAdd(3)", "addAndGet(3)", "incrementAndGet()", "decrementAndGet()",
            "getAndIncrement()", "getAndDecrement()",
        ]
        let coreCalls = ["get()", "set(VALUE)", "getAndSet(VALUE)"]
        let updateCalls = ["getAndUpdate { it }", "updateAndGet { it }"]
        let calls = [
            ("ai", arithmeticCalls + coreCalls.map { $0.replacingOccurrences(of: "VALUE", with: "3") } + updateCalls),
            ("al", arithmeticCalls.map { $0.replacingOccurrences(of: "(3)", with: "(3L)") }
                + coreCalls.map { $0.replacingOccurrences(of: "VALUE", with: "3L") } + updateCalls),
            ("ar", coreCalls.map { $0.replacingOccurrences(of: "VALUE", with: "\"z\"") } + updateCalls),
            ("ab", coreCalls.map { $0.replacingOccurrences(of: "VALUE", with: "false") } + updateCalls),
        ].flatMap { receiver, methods in methods.map { "\(receiver).\($0)" } }
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        import kotlin.concurrent.atomics.*
        import kotlin.concurrent.getAndAdd
        import kotlin.concurrent.getAndUpdate
        import kotlin.concurrent.updateAndGet
        fun main() {
            val ai = AtomicInt(0)
            val al = AtomicLong(0L)
            val ar = AtomicReference("x")
            val ab = AtomicBoolean(true)
            \(calls.joined(separator: "\n    "))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == calls.count, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0024" }, "\(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let memberCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, _, _, _, range) = ast.arena.expr(id),
                      ctx.sourceManager.origin(of: range.start.file) == .user
                else { return nil }
                return id
            }
            #expect(memberCalls.count == calls.count)
            for call in memberCalls {
                #expect(sema.bindings.callBinding(for: call) == nil)
            }
        }
    }

    @Test
    func javaAndLegacyAliasesAndUserExtensionsRemainCallable() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        import kotlin.concurrent.atomics.*
        import java.util.concurrent.atomic.AtomicInteger
        import kotlin.concurrent.AtomicInt as LegacyInt
        import kotlin.concurrent.AtomicReference as LegacyReference
        fun AtomicInt.getAndAdd(delta: Int): Int = fetchAndAdd(delta)
        fun main() {
            val java = AtomicInteger(0)
            java.getAndAdd(3)
            java.addAndGet(3)
            java.incrementAndGet()
            java.decrementAndGet()
            java.getAndIncrement()
            java.getAndDecrement()
            java.getAndSet(0)
            java.get()
            java.set(0)
            val legacy = LegacyInt(0)
            legacy.getAndAdd(3)
            legacy.incrementAndGet()
            val reference = LegacyReference("x")
            reference.getAndSet("z")
            val canonical = AtomicInt(0)
            canonical.getAndAdd(3)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
