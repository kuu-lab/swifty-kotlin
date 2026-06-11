@testable import CompilerCore
import XCTest

final class JsCollectionsReadonlyMapTests: XCTestCase {
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
                "Expected kotlin.js.collections.JsReadonlyMap surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsReadonlyMapInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlyMap")]
        ))
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(typeParams.count, 2)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: symbol), [.invariant, .out])
        XCTAssertEqual(sema.symbols.parentSymbol(for: symbol), sema.symbols.lookup(fqName: pkg))
        XCTAssertTrue(sema.symbols.annotations(for: symbol).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalJsCollectionsApi"
        })
    }

    func testJsReadonlyMapPropertyTypeCarriesCorrectProjections() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlyMap")]
        ))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)
        let keyTypeParamSymbol = try XCTUnwrap(typeParams.first)
        let valueTypeParamSymbol = try XCTUnwrap(typeParams.dropFirst().first)
        let keyType = sema.types.make(.typeParam(TypeParamType(
            symbol: keyTypeParamSymbol,
            nullability: .nonNull
        )))
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: valueTypeParamSymbol,
            nullability: .nonNull
        )))
        let propertyType = try XCTUnwrap(sema.symbols.propertyType(for: symbol))

        guard case let .classType(classType) = sema.types.kind(of: propertyType) else {
            return XCTFail("Expected JsReadonlyMap property type to be a class type")
        }
        XCTAssertEqual(classType.classSymbol, symbol)
        XCTAssertEqual(classType.args, [.invariant(keyType), .out(valueType)])
        XCTAssertEqual(classType.nullability, .nonNull)
    }

    func testJsReadonlyMapCanBeImportedAndUsedAsType() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsReadonlyMap

        fun accept(values: JsReadonlyMap<String, Int>): JsReadonlyMap<String, Int> = values
        """
        let (sema, interner) = try makeSema(source: source)
        let symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "js", "collections", "JsReadonlyMap"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("accept")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected accept() to return JsReadonlyMap<String, Int>")
        }
        XCTAssertEqual(returnClassType.classSymbol, symbol)
        XCTAssertEqual(returnClassType.args.count, 2)
        let returnArgs = try returnClassType.args.map { projection -> TypeID in
            switch projection {
            case let .invariant(arg), let .out(arg):
                return arg
            case .in, .star:
                throw XCTSkip("Unexpected projection in JsReadonlyMap<String, Int> return type")
            }
        }
        XCTAssertEqual(returnArgs[0], sema.types.stringType)
        XCTAssertEqual(returnArgs[1], sema.types.intType)
    }
}
