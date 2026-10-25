@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LocalOperatorFunctionParsingTests {
    @Test
    func operatorAttributeSurvivesParsingAndSnapshot() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        fun probe() {
            operator fun Int.unaryPlus(): Int = this
            fun Int.unaryMinus(): Int = this
            infix fun Int.plus(other: Int): Int = this + other
        }
        """.utf8))
        try runFrontend(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let arena = try #require(ctx.ast?.arena)
        let functions = arena.exprs.indices.filter {
            if case .localFunDecl = arena.exprs[$0] { return true }
            return false
        }.map { ExprID(rawValue: Int32($0)) }
        #expect(functions.count == 3)
        let operatorID = try #require(functions.first)
        #expect(arena.isOperatorFunction(operatorID))
        #expect(functions.dropFirst().allSatisfy { !arena.isOperatorFunction($0) })
        #expect(arena.isInfixFunction(try #require(functions.last)))

        let encoded = try JSONEncoder().encode(arena.snapshot())
        let restored = ASTArena(snapshot: try JSONDecoder().decode(ASTArenaSnapshot.self, from: encoded))
        #expect(restored.isOperatorFunction(operatorID))
        #expect(functions.dropFirst().allSatisfy { !restored.isOperatorFunction($0) })
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "operatorFunctionExpressions")
        let legacySnapshot = try JSONDecoder().decode(
            ASTArenaSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        #expect(legacySnapshot.operatorFunctionExpressions.isEmpty)
    }

    @Test(arguments: [
        ("private fun helper() {}", "KSWIFTK-SEMA-0400"),
        ("inline fun helper() {}", "KSWIFTK-SEMA-0400"),
        ("operator fun Int.notAnOperator(): Int = this", "KSWIFTK-SEMA-0416"),
        ("operator fun mod(a: Int): Int = a", "KSWIFTK-SEMA-0416"),
        // KUU-3149: local operator functions are never members, so only the
        // extension-receiver form with the convention arity is legal.
        ("operator fun plus(a: Int, b: Int): Int = a", "KSWIFTK-SEMA-0439"),
        ("operator fun unaryPlus(): Int = 1", "KSWIFTK-SEMA-0439"),
        ("operator fun Int.unaryPlus(a: Int): Int = a", "KSWIFTK-SEMA-0439"),
        ("operator fun Int.plus(a: Int, b: Int): Int = a", "KSWIFTK-SEMA-0439"),
        ("operator fun Int.component1(a: Int): Int = a", "KSWIFTK-SEMA-0439"),
        ("operator fun Int.plus(vararg a: Int): Int = a.size", "KSWIFTK-SEMA-0439"),
        ("operator fun Int.plus(a: Int = 0): Int = a", "KSWIFTK-SEMA-0439"),
    ])
    func invalidLocalModifiersRemainRejected(declaration: String, diagnostic: String) throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("fun probe() { \(declaration) }".utf8))
        try runFrontend(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == diagnostic })
    }
}
