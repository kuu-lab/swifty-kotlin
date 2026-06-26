@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-001: Validates that `CharSequence.all(predicate)` resolves
/// through Sema for String receivers and lowers through the bundled Kotlin
/// source implementation. The source surface signature is
/// `String.all(predicate: (Char) -> Boolean): Boolean`.
final class StringAllFunctionTests: XCTestCase {
    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            results.append(exprID)
        }
        return results
    }

    /// Sema should accept `String.all { predicate }` with a `(Char) -> Boolean`
    /// lambda and resolve the result type to `Boolean`.
    func testStringAllResolvesAndReturnsBoolean() throws {
        let source = """
        fun allDigits(value: String): Boolean {
            return value.all { c -> c.isDigit() }
        }

        fun allUppercase(): Boolean {
            return "HELLO".all { it.isUpperCase() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected String.all to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callIDs = allMemberCallExprIDs(named: "all", in: ast, interner: ctx.interner)
            XCTAssertEqual(callIDs.count, 2, "Expected two String.all call sites")
            for callID in callIDs {
                let exprType = try XCTUnwrap(sema.bindings.exprType(for: callID))
                XCTAssertEqual(
                    exprType,
                    sema.types.booleanType,
                    "String.all should be typed as Boolean"
                )
            }
        }
    }

    /// Sema should expose `String.all` as a bundled Kotlin source extension
    /// function instead of a synthetic runtime ABI stub.
    func testStringAllResolvesToBundledSourceFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "all"].map { ctx.interner.intern($0) }
            let stringReceiverSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    guard signature.receiverType == sema.types.stringType,
                          signature.parameterTypes.count == 1
                    else { return false }
                    return signature.returnType == sema.types.booleanType
                },
                "Expected String.all bundled source function to be registered"
            )
            XCTAssertNil(sema.symbols.externalLinkName(for: stringReceiverSymbol))
            XCTAssertFalse(
                sema.symbols.symbol(stringReceiverSymbol)?.flags.contains(.synthetic) ?? true,
                "String.all should now be a parsed Kotlin source function"
            )
        }
    }

    /// Lowering should keep `String.all` as a source function call and avoid
    /// reintroducing the old `kk_string_all` runtime ABI call site.
    func testStringAllDoesNotLowerToRuntimeHelper() throws {
        let source = """
        fun main() {
            val numeric = "123"
            numeric.all { it.isDigit() }
            val letters = "abc"
            letters.all { it.isLetter() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertFalse(
                callees.contains("kk_string_all"),
                "String.all should lower through bundled Kotlin source, got: \(callees)"
            )
        }
    }
}
