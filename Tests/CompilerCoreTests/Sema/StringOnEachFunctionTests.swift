@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-039: Validates that `String.onEach(action)` resolves
/// through Sema and lowers to the runtime helper `kk_string_onEach`.
/// The synthetic surface signature is
/// `String.onEach(action: (Char) -> Unit): String`.
final class StringOnEachFunctionTests: XCTestCase {
    func testStringOnEachResolvesAndReturnsString() throws {
        let source = """
        fun logChars(value: String): String {
            return value.onEach { c -> print(c) }
        }

        fun logLiteral(): String {
            return "hello".onEach { print(it) }
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
                "Expected String.onEach to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            var callIDs: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "onEach"
                else { continue }
                callIDs.append(exprID)
            }
            XCTAssertEqual(callIDs.count, 2, "Expected two String.onEach call sites")
            for callID in callIDs {
                let exprType = try XCTUnwrap(sema.bindings.exprType(for: callID))
                XCTAssertEqual(
                    exprType,
                    sema.types.stringType,
                    "String.onEach should be typed as String"
                )
            }
        }
    }

    func testStringOnEachLinksToRuntimeHelper() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "onEach"].map { ctx.interner.intern($0) }
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
                "Expected String.onEach synthetic to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: stringReceiverSymbol),
                "kk_string_onEach"
            )
        }
    }

    func testStringOnEachLowersToRuntimeHelper() throws {
        let source = """
        fun main() {
            val s = "abc"
            s.onEach { print(it) }
            "xyz".onEach { c -> print(c) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            let onEachFlags = try XCTUnwrap(
                throwFlags["kk_string_onEach"],
                "Expected kk_string_onEach call sites to appear in main()"
            )
            XCTAssertEqual(onEachFlags.count, 2, "Expected two kk_string_onEach invocations")
        }
    }
}
