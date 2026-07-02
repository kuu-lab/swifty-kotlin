@testable import CompilerCore
import XCTest

final class KSwiftKRuntimeNameAnnotationTests: XCTestCase {
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
                "Expected KSwiftK runtime annotation surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKSwiftKRuntimeNameAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kswiftk", "internal", "KSwiftKRuntimeName"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kswiftk.internal.KSwiftKRuntimeName must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testKSwiftKRuntimeNameCarriesExpectedMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kswiftk", "internal", "KSwiftKRuntimeName"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "KSwiftKRuntimeName must carry @Target metadata"
        )
        let retention = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "KSwiftKRuntimeName must carry @Retention metadata"
        )

        XCTAssertEqual(target.arguments, ["AnnotationTarget.FUNCTION"])
        XCTAssertEqual(retention.arguments, ["AnnotationRetention.BINARY"])
    }

    func testKSwiftKRuntimeNamePropertyAndConstructorAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let baseFQName = ["kswiftk", "internal", "KSwiftKRuntimeName"].map { interner.intern($0) }
        let annotationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: baseFQName))
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: baseFQName + [interner.intern("name")]),
            "KSwiftKRuntimeName.name property must be registered"
        )
        let constructorSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: baseFQName + [interner.intern("<init>")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .constructor
            },
            "KSwiftKRuntimeName String constructor must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
        let propertyInfo = try XCTUnwrap(sema.symbols.symbol(propertySymbol))

        XCTAssertEqual(propertyInfo.kind, .property)
        XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), annotationSymbol)
        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType])
    }

    func testKSwiftKRuntimeNameSetsExternalLinkNameOnFunction() throws {
        let source = """
        package demo
        import kswiftk.internal.KSwiftKRuntimeName
        @KSwiftKRuntimeName("kk_char_isDigit")
        external fun runtimeIsDigit(ch: Char): Boolean
        """
        let (sema, interner) = try makeSema(source: source)
        let functionFQName = ["demo", "runtimeIsDigit"].map { interner.intern($0) }
        let function = try XCTUnwrap(sema.symbols.lookup(fqName: functionFQName))

        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_char_isDigit")
    }
}
