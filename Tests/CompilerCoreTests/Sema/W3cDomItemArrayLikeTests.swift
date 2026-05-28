@testable import CompilerCore
import XCTest

final class W3cDomItemArrayLikeTests: XCTestCase {
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
                "Expected org.w3c.dom.ItemArrayLike surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testItemArrayLikeInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["org", "w3c", "dom"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: pkg + [interner.intern("ItemArrayLike")]),
            "org.w3c.dom.ItemArrayLike must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testItemArrayLikeHasSingleOutTypeParameter() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["org", "w3c", "dom"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: pkg + [interner.intern("ItemArrayLike")])
        )
        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)

        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: symbol), [.out])
    }

    func testItemArrayLikeParentIsW3cDomPackage() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["org", "w3c", "dom"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: pkg + [interner.intern("ItemArrayLike")])
        )
        XCTAssertEqual(
            sema.symbols.parentSymbol(for: symbol),
            sema.symbols.lookup(fqName: pkg)
        )
    }

    func testItemArrayLikePropertyTypeCarriesOutProjection() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["org", "w3c", "dom"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: pkg + [interner.intern("ItemArrayLike")])
        )
        let typeParamSymbol = try XCTUnwrap(
            sema.types.nominalTypeParameterSymbols(for: symbol).first
        )
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let propertyType = try XCTUnwrap(sema.symbols.propertyType(for: symbol))

        guard case let .classType(classType) = sema.types.kind(of: propertyType) else {
            return XCTFail("Expected ItemArrayLike property type to be a class type")
        }
        XCTAssertEqual(classType.classSymbol, symbol)
        XCTAssertEqual(classType.args, [.out(typeParamType)])
        XCTAssertEqual(classType.nullability, .nonNull)
    }

    func testItemArrayLikeCanBeUsedAsType() throws {
        let source = """
        import org.w3c.dom.ItemArrayLike

        fun accept(values: ItemArrayLike<String>): ItemArrayLike<String> = values
        """
        let (sema, interner) = try makeSema(source: source)
        let pkg = ["org", "w3c", "dom"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: pkg + [interner.intern("ItemArrayLike")])
        )
        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("accept")])
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected accept() to return ItemArrayLike<String>")
        }
        XCTAssertEqual(returnClassType.classSymbol, symbol)
        let returnArg: TypeID
        switch try XCTUnwrap(returnClassType.args.first) {
        case let .invariant(arg), let .out(arg):
            returnArg = arg
        case .in, .star:
            return XCTFail("Expected accept() to return ItemArrayLike<String> with out/invariant projection")
        }
        XCTAssertEqual(returnArg, sema.types.stringType)
    }
}
