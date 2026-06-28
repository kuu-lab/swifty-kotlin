@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-040: Validates that `String.onEachIndexed(action)` resolves
/// through Sema and lowers to the runtime helper `kk_string_onEachIndexed`.
/// The synthetic surface signature is
/// `String.onEachIndexed(action: (Int, Char) -> Unit): String`.
final class StringOnEachIndexedFunctionTests: XCTestCase {
    func testStringOnEachIndexedResolvesAndReturnsString() throws {
        let source = """
        fun logIndexedChars(value: String): String {
            return value.onEachIndexed { i, c -> print("$i:$c") }
        }

        fun logLiteralIndexed(): String {
            return "hello".onEachIndexed { index, ch -> print(index) }
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
                "Expected String.onEachIndexed to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            var callIDs: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "onEachIndexed"
                else { continue }
                callIDs.append(exprID)
            }
            XCTAssertEqual(callIDs.count, 2, "Expected two String.onEachIndexed call sites")
            for callID in callIDs {
                let exprType = try XCTUnwrap(sema.bindings.exprType(for: callID))
                XCTAssertEqual(
                    exprType,
                    sema.types.stringType,
                    "String.onEachIndexed should be typed as String"
                )
            }
        }
    }

    func testStringOnEachIndexedLinksToRuntimeHelper() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "onEachIndexed"].map { ctx.interner.intern($0) }
            let stringReceiverSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    guard signature.receiverType == sema.types.stringType,
                          signature.parameterTypes.count == 1
                    else { return false }
                    return signature.returnType == sema.types.stringType
                },
                "Expected String.onEachIndexed synthetic to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: stringReceiverSymbol),
                "kk_string_onEachIndexed"
            )
        }
    }

    func testStringOnEachIndexedLowersToRuntimeHelper() throws {
        let source = """
        fun main() {
            val s = "abc"
            s.onEachIndexed { i, c -> print(i) }
            "xyz".onEachIndexed { index, ch -> print(ch) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            let onEachIndexedFlags = try XCTUnwrap(
                throwFlags["kk_string_onEachIndexed"],
                "Expected kk_string_onEachIndexed call sites to appear in main()"
            )
            XCTAssertEqual(onEachIndexedFlags.count, 2, "Expected two kk_string_onEachIndexed invocations")
        }
    }
}
