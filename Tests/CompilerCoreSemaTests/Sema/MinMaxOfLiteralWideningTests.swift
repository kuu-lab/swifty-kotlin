#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4167: an unsuffixed integer literal keeps its integer-literal type
/// through minOf/maxOf overload resolution, so it adapts to the wider
/// primitive parameter selected by a sibling argument (`maxOf(1, 2L)` binds
/// `maxOf(Long, Long)` like kotlinc).
@Suite
struct MinMaxOfLiteralWideningTests {
    @Test func integerLiteralAdoptsLongParameterOfFixedArityOverload() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(maxOf(1, 2L))
            println(minOf(1, 2L))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["maxOf", "minOf"] {
            let call = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, args, _) = expr, args.count == 2,
                      case let .nameRef(identifier, _) = ast.arena.expr(callee) else { return false }
                return ctx.interner.resolve(identifier) == name
            }, "Expected \(name)(1, 2L) call")
            #expect(sema.bindings.exprType(for: call) == sema.types.longType)
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(signature.typeParameterSymbols.isEmpty)
            #expect(signature.parameterTypes == [sema.types.longType, sema.types.longType])
        }
    }

    @Test func integerLiteralAdoptsLongParameterOfThreeArgOverload() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(maxOf(1, 2, 3L))
            println(minOf(1, 2L, 3))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["maxOf", "minOf"] {
            let call = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, args, _) = expr, args.count == 3,
                      case let .nameRef(identifier, _) = ast.arena.expr(callee) else { return false }
                return ctx.interner.resolve(identifier) == name
            }, "Expected \(name) 3-arg call")
            #expect(sema.bindings.exprType(for: call) == sema.types.longType)
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(signature.typeParameterSymbols.isEmpty)
            #expect(signature.parameterTypes == [
                sema.types.longType, sema.types.longType, sema.types.longType,
            ])
        }
    }

    @Test func integerLiteralAdoptsLongParameterBesideDeclaredLong() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val x = 5L
            println(maxOf(1, x))
            println(minOf(x, 2))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["maxOf", "minOf"] {
            let call = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, args, _) = expr, args.count == 2,
                      case let .nameRef(identifier, _) = ast.arena.expr(callee) else { return false }
                return ctx.interner.resolve(identifier) == name
            }, "Expected \(name) call beside declared Long")
            #expect(sema.bindings.exprType(for: call) == sema.types.longType)
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(signature.parameterTypes == [sema.types.longType, sema.types.longType])
        }
    }

    @Test func integerLiteralAdoptsLongParameterWhenLiteralExceedsInt() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(maxOf(1, 5000000000))
            println(minOf(1, 5000000000))
            println(maxOf(1, 2, 5000000000))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["maxOf", "minOf"] {
            let call = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, args, _) = expr, args.count == 2,
                      case let .nameRef(identifier, _) = ast.arena.expr(callee) else { return false }
                return ctx.interner.resolve(identifier) == name
            }, "Expected \(name)(1, 5000000000) call")
            #expect(sema.bindings.exprType(for: call) == sema.types.longType)
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(signature.parameterTypes == [sema.types.longType, sema.types.longType])
        }
        let threeArg = try #require(firstExprID(in: ast) { _, expr in
            guard case let .call(callee, _, args, _) = expr, args.count == 3,
                  case let .nameRef(identifier, _) = ast.arena.expr(callee) else { return false }
            return ctx.interner.resolve(identifier) == "maxOf"
        }, "Expected maxOf(1, 2, 5000000000) call")
        let chosen = try #require(sema.bindings.callBinding(for: threeArg)?.chosenCallee)
        let signature = try #require(sema.symbols.functionSignature(for: chosen))
        #expect(signature.parameterTypes == [
            sema.types.longType, sema.types.longType, sema.types.longType,
        ])
    }

    @Test func declaredIntegerMismatchStillRejected() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val i = 1
            val b: Byte = 1
            val s: Short = 2
            println(maxOf(i, 2L))
            println(maxOf(b, s))
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func mixedFloatingPointLiteralStillRejected() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(maxOf(1, 2.0))
            println(maxOf(1.0, 2))
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    /// kotlinc accepts mixed signed/unsigned literal calls like
    /// `maxOf(1, 2u)` but emits code that crashes with ClassCastException at
    /// runtime; kswiftc keeps rejecting them.
    @Test func mixedUnsignedLiteralStillRejected() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(maxOf(1, 2u))
            println(maxOf(1u, 2))
            println(maxOf(1, 2uL))
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
