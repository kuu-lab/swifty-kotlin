#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-645: `kotlin.experimental` の Byte/Short 版 `and`/`or`/`xor`/`inv`。
///
/// KSwiftK の型システムには byte/short プリミティブが存在せず、`Byte`/`Short`
/// の型注釈は `Int` へ解決される（`PrimitiveType` に byte/short が無く、
/// `toByte()`/`toShort()` の戻り型も `intType`）。そのため本家の
/// `Byte.and(Byte): Byte` 等は独立した宣言としては表現できず、これらの呼び出しは
/// `CallTypeChecker+MemberCallInferenceRegularPrimitiveSpecials.swift` の Int 特例で
/// 解決される。値としては kotlinc と一致する（`Scripts/diff_cases/byte_short_bitwise_basic.kt`）。
///
/// このテストは、その解決経路と「Int 幅を保つ」性質を固定する。Byte/Short を
/// 独立プリミティブ化する際は、ここが最初に落ちる。
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
        // Byte/Short are modeled as Int, so the receiver type is the result type.
        let receiverType = sema.types.intType

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
