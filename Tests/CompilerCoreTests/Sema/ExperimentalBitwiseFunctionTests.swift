#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-645: `kotlin.experimental` の Byte/Short 版 `and`/`or`/`xor`/`inv`。
///
/// `Byte`/`Short` は独立したプリミティブ型として解決される。
/// これらの呼び出しは `CallTypeChecker+MemberCallInferenceRegularPrimitiveSpecials.swift`
/// の数値特例で解決され、受信型を保つ。値としては kotlinc と一致する
/// （`Scripts/diff_cases/byte_short_bitwise_basic.kt`）。
///
/// このテストは、Byte/Short のビット演算が受信型を保つことを固定する。
@Suite
struct ExperimentalBitwiseFunctionTests {
    private static let bitwiseImports = """
    import kotlin.experimental.and
    import kotlin.experimental.inv
    import kotlin.experimental.or
    import kotlin.experimental.xor
    """

    @Test func testByteBitwiseOperationsResolveWithoutDiagnostics() throws {
        let ctx = makeContextFromSource("""
        \(Self.bitwiseImports)

        fun byteOps(a: Byte, b: Byte) {
            println(a and b)
            println(a or b)
            println(a xor b)
            println(a.inv())
            println(a.and(b))
            println(a.or(b))
            println(a.xor(b))
        }
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Byte bitwise operations to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    @Test func testShortBitwiseOperationsResolveWithoutDiagnostics() throws {
        let ctx = makeContextFromSource("""
        \(Self.bitwiseImports)

        fun shortOps(a: Short, b: Short) {
            println(a and b)
            println(a or b)
            println(a xor b)
            println(a.inv())
            println(a.and(b))
            println(a.or(b))
            println(a.xor(b))
        }
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Short bitwise operations to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    @Test(arguments: ["Byte", "Short"])
    func testBitwiseResultKeepsReceiverType(_ receiverTypeName: String) throws {
        let ctx = makeContextFromSource("""
        \(Self.bitwiseImports)

        fun ops(a: \(receiverTypeName), b: \(receiverTypeName)) {
            println(a and b)
            println(a.inv())
        }
        """)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        // Byte/Short are distinct primitives; bitwise operations keep the receiver type.
        let receiverType: TypeID = switch receiverTypeName {
        case "Byte": sema.types.byteType
        case "Short": sema.types.shortType
        default: sema.types.errorType
        }

        for name in ["and", "inv"] {
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == name
            }, "Expected \(receiverTypeName).\(name) member call")
            #expect(
                sema.bindings.exprType(for: callExpr) == receiverType,
                "\(receiverTypeName).\(name) should keep the receiver type"
            )
        }
    }

    /// `kotlin.experimental` の import があっても Int の bitwise 演算は Int 幅のまま。
    /// Byte 版を Kotlin ソースとして宣言すると（Byte ≡ Int のため）Int の演算が
    /// 8bit へ切り詰められる実装に乗っ取られるので、その退行を検出する。
    @Test func testIntBitwiseIsNotNarrowedByExperimentalImports() throws {
        let ctx = makeContextFromSource("""
        \(Self.bitwiseImports)

        fun intOps(): Int {
            val wide: Int = 0x1234 and 0xFF00
            return wide
        }
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected Int bitwise operations to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "and"
        }, "Expected Int.and member call")
        #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
    }
}
#endif
