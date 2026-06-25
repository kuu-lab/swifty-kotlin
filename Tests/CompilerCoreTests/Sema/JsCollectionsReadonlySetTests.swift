@testable import CompilerCore
import XCTest

/// STDLIB-JS-COLLECTIONS-FN-006: Verifies that `JsReadonlySet<E>.toSet()` is
/// correctly registered on the Kotlin/JS `JsReadonlySet` interface surface.
final class JsCollectionsReadonlySetTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected JsReadonlySet surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsReadonlySetToSetMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let fqName = pkg + [interner.intern("JsReadonlySet"), interner.intern("toSet")]
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected JsReadonlySet.toSet to be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(info.kind, .function)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJsReadonlySetToSetLinksToKkSetToSet() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let fqName = pkg + [interner.intern("JsReadonlySet"), interner.intern("toSet")]
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_set_to_set"
        )
    }

    func testJsReadonlySetToSetReturnsKotlinSet() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let toSetFQName = jsPkg + [interner.intern("JsReadonlySet"), interner.intern("toSet")]
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: toSetFQName))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))

        guard case let .classType(returnClass) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected toSet() return type to be a classType")
        }
        let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
        let setSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Set")]),
            "Expected kotlin.collections.Set to be registered"
        )
        XCTAssertEqual(returnClass.classSymbol, setSymbol, "Expected toSet() to return kotlin.collections.Set")
        XCTAssertEqual(returnClass.args.count, 1)
        if case let .out(elementType) = returnClass.args.first {
            guard case let .typeParam(tp) = sema.types.kind(of: elementType) else {
                return XCTFail("Expected out-projected element to be a type parameter")
            }
            XCTAssertEqual(tp.symbol, signature.typeParameterSymbols.first)
        } else {
            XCTFail("Expected Set<out E> projection")
        }
    }

    func testJsReadonlySetToSetReceivesJsReadonlySetReceiver() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let toSetFQName = jsPkg + [interner.intern("JsReadonlySet"), interner.intern("toSet")]
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: toSetFQName))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))

        guard let receiverType = signature.receiverType,
              case let .classType(receiverClass) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected toSet() to have a JsReadonlySet receiver")
        }
        let readonlySetSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: jsPkg + [interner.intern("JsReadonlySet")])
        )
        XCTAssertEqual(receiverClass.classSymbol, readonlySetSymbol)
    }

    func testJsReadonlySetToSetResolvesInCallExpression() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsReadonlySet

        fun probe(s: JsReadonlySet<Int>): Set<Int> = s.toSet()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected JsReadonlySet.toSet() call to compile cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "toSet"
                },
                "Expected a .toSet() member call in the AST"
            )
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_set_to_set",
                "Expected JsReadonlySet.toSet() to resolve to kk_set_to_set"
            )
        }
    }
}
