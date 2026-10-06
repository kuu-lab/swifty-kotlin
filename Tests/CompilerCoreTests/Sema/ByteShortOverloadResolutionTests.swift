#if canImport(Testing)
@testable import CompilerCore
import Testing

/// BUG-186: Byte/Short overloads must be distinct and resolve to the correct overload.
@Suite
struct ByteShortOverloadResolutionTests {
    @Test func unsignedLiteralComparisonVarargsPreferUInt() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println(maxOf(1u, 2u, 3u, 4u))
            println(minOf(1u, 2u, 3u, 4u))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["maxOf", "minOf"] {
            let call = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, args, _) = expr, args.count == 4,
                      case let .nameRef(identifier, _) = ast.arena.expr(callee) else { return false }
                return ctx.interner.resolve(identifier) == name
            })
            #expect(sema.bindings.exprType(for: call) == sema.types.uintType)
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(signature.typeParameterSymbols.isEmpty)
            #expect(signature.parameterTypes == [sema.types.uintType, sema.types.uintType])
            #expect(signature.valueParameterIsVararg == [false, true])
        }
        let warnings = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("ExperimentalUnsignedTypes")
        }
        #expect(warnings.count == 2)
    }

    @Test func testIntegerLiteralsResolveAndBindToVarargElementType() throws {
        let source = """
            package sample
            fun f(vararg bytes: Byte): Int = bytes.size
            fun f(vararg bytes: UByte): Int = bytes.size
            fun unsigned(vararg bytes: UByte): Int = bytes.size
            fun wider(vararg values: Byte): Int = 1
            fun wider(vararg values: Int): Int = 2
            fun narrower(vararg values: Byte): Int = 1
            fun narrower(vararg values: Short): Int = 2
            fun main() {
                f(65, 66)
                f(-1, 127)
                unsigned(255u)
                wider(42)
                narrower(43)
            }
            """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Integer literals should resolve as vararg elements: \(ctx.diagnostics.diagnostics.map { $0.message })")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let literal = try #require(firstExprID(in: ast, path: paths[0], ctx: ctx) { _, expr in
                if case let .intLiteral(value, _) = expr { return value == 65 }
                return false
            })
            #expect(sema.bindings.exprType(for: literal) == sema.types.byteType)
            let unsignedLiteral = try #require(firstExprID(in: ast, path: paths[0], ctx: ctx) { _, expr in
                if case let .uintLiteral(value, _) = expr { return value == 255 }
                return false
            })
            #expect(sema.bindings.exprType(for: unsignedLiteral) == sema.types.ubyteType)
            let intLiteral = try #require(firstExprID(in: ast, path: paths[0], ctx: ctx) { _, expr in
                if case let .intLiteral(value, _) = expr { return value == 42 }
                return false
            })
            #expect(sema.bindings.exprType(for: intLiteral) == sema.types.intType)
            let shortLiteral = try #require(firstExprID(in: ast, path: paths[0], ctx: ctx) { _, expr in
                if case let .intLiteral(value, _) = expr { return value == 43 }
                return false
            })
            #expect(sema.bindings.exprType(for: shortLiteral) == sema.types.shortType)
        }
    }

    @Test func testOutOfRangeVarargLiteralDoesNotNarrowToByte() throws {
        let source = """
            package sample
            fun onlyByte(vararg bytes: Byte): Int = bytes.size
            fun main() { onlyByte(128) }
            """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test func testByteAndShortOverloadsAndArrayLiteralNarrowing() throws {
        let sources: [String] = [
            """
            package sample0

            fun f(x: Byte): String = "byte"
            fun f(x: Short): String = "short"

            fun main() {
                println(f(1.toByte()))
                println(f(1.toShort()))
            }
            """,
            """
            package sample1

            fun main() {
                val bytes = byteArrayOf(1, 2, 3)
                bytes[0] = 9
                val shorts = shortArrayOf(1, 2, 3)
                shorts[0] = 9
                bytes.binarySearch(3)
                shorts.binarySearch(2)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected Byte/Short overloads and array operations to resolve without errors: \(ctx.diagnostics.diagnostics.map { $0.message })")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let toByteCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toByte"
            }, "Expected 1.toByte() call")
            #expect(sema.bindings.exprType(for: toByteCall) == sema.types.byteType, "1.toByte() should have type Byte")

            let toShortCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toShort"
            }, "Expected 1.toShort() call")
            #expect(sema.bindings.exprType(for: toShortCall) == sema.types.shortType, "1.toShort() should have type Short")
        }
    }
}
#endif
