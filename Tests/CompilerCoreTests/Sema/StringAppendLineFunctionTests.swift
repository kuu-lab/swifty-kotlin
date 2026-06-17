@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-004: Validates that `StringBuilder.appendLine` overloads resolve
/// through Sema and dispatch to the runtime link names used by the typed
/// StringBuilder bridge.
final class StringAppendLineFunctionTests: XCTestCase {
    private func memberCallExprIDs(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - appendLine(value) overload

    func testAppendLineWithValueResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine("hello")
            sb.appendLine("world")
            println(sb.toString())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected appendLine(String) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - appendLine() no-arg overload

    func testAppendLineNoArgResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine()
            println(sb.toString())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected appendLine() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - appendLine returns StringBuilder (chaining)

    func testAppendLineChainingResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val result = StringBuilder()
                .appendLine("first")
                .appendLine("second")
                .appendLine()
                .toString()
            println(result)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected chained appendLine calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Runtime link name registration

    func testAppendLineWithValueLinksToCorrectRuntimeSymbol() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine("test")
        }
        """)
        try runSema(ctx)
        let interner = ctx.interner
        let sema = ctx.sema!
        let sbSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("appendLine"),
        ])
        let valueOverload = sbSymbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.count == 1
                && sema.symbols.externalLinkName(for: symbolID) == "kk_string_builder_append_line_obj"
        }
        XCTAssertNotNil(valueOverload, "appendLine(value) overload should be registered")
        if let sym = valueOverload {
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                "kk_string_builder_append_line_obj",
                "appendLine(value) should link to kk_string_builder_append_line_obj"
            )
        }
    }

    func testAppendLineTypedOverloadsLinkToTypedRuntimeSymbols() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            val f: Float = 1.5f
            val d: Double = 2.25
            sb.appendLine('x')
            sb.appendLine(true)
            sb.appendLine(f)
            sb.appendLine(d)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected typed appendLine overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = ctx.ast!
        let sema = ctx.sema!
        let links = memberCallExprIDs(named: "appendLine", in: ast, interner: ctx.interner).compactMap { exprID -> String? in
            guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else {
                return nil
            }
            return sema.symbols.externalLinkName(for: chosen)
        }

        XCTAssertTrue(links.contains("kk_string_builder_append_line_char_obj"))
        XCTAssertTrue(links.contains("kk_string_builder_append_line_bool_obj"))
        XCTAssertTrue(links.contains("kk_string_builder_append_line_float_obj"))
        XCTAssertTrue(links.contains("kk_string_builder_append_line_double_obj"))
    }

    func testAppendLineNoArgLinksToCorrectRuntimeSymbol() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine()
        }
        """)
        try runSema(ctx)
        let interner = ctx.interner
        let sema = ctx.sema!
        let sbSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("appendLine"),
        ])
        let noArgOverload = sbSymbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.isEmpty
        }
        XCTAssertNotNil(noArgOverload, "appendLine() no-arg overload should be registered")
        if let sym = noArgOverload {
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                "kk_string_builder_append_line_noarg_obj",
                "appendLine() should link to kk_string_builder_append_line_noarg_obj"
            )
        }
    }
}
