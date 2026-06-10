@testable import CompilerCore
import XCTest

final class JsCollectionsReadonlyArrayTests: XCTestCase {
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
                "Expected kotlin.js.collections.JsReadonlyArray surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsReadonlyArrayInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let readonlyArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlyArray")]
        ))
        let info = try XCTUnwrap(sema.symbols.symbol(readonlyArraySymbol))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: readonlyArraySymbol)

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: readonlyArraySymbol), [.out])
        XCTAssertEqual(sema.symbols.parentSymbol(for: readonlyArraySymbol), sema.symbols.lookup(fqName: pkg))
        XCTAssertTrue(sema.symbols.annotations(for: readonlyArraySymbol).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalJsCollectionsApi"
        })
    }

    func testJsReadonlyArrayPropertyTypeCarriesOutElementProjection() throws {
        let (sema, interner) = try makeSema()
        let readonlyArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "js", "collections", "JsReadonlyArray"].map { interner.intern($0) }
        ))
        let typeParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: readonlyArraySymbol).first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let propertyType = try XCTUnwrap(sema.symbols.propertyType(for: readonlyArraySymbol))

        guard case let .classType(classType) = sema.types.kind(of: propertyType) else {
            return XCTFail("Expected JsReadonlyArray property type to be a class type")
        }
        XCTAssertEqual(classType.classSymbol, readonlyArraySymbol)
        XCTAssertEqual(classType.args, [.out(typeParamType)])
        XCTAssertEqual(classType.nullability, .nonNull)
    }

    func testJsReadonlyArrayCanBeImportedAndUsedAsType() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsReadonlyArray

        fun accept(values: JsReadonlyArray<String>): JsReadonlyArray<String> = values
        """
        let (sema, interner) = try makeSema(source: source)
        let readonlyArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "js", "collections", "JsReadonlyArray"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("accept")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected accept() to return JsReadonlyArray<String>")
        }
        XCTAssertEqual(returnClassType.classSymbol, readonlyArraySymbol)
        let returnArg: TypeID
        switch try XCTUnwrap(returnClassType.args.first) {
        case let .invariant(arg), let .out(arg):
            returnArg = arg
        case .in, .star:
            return XCTFail("Expected accept() to return JsReadonlyArray<String>")
        }
        XCTAssertEqual(returnArg, sema.types.stringType)
    }
}
