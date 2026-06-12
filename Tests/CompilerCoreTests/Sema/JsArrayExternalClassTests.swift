@testable import CompilerCore
import XCTest

final class JsArrayExternalClassTests: XCTestCase {
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
                "Expected JsArray external class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsArrayClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsArray"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsArray must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }



    func testJsArrayConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsArrayFQName = ["kotlin", "js", "JsArray"].map { interner.intern($0) }
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: jsArrayFQName))
        let typeParamSymbol = try XCTUnwrap(
            sema.types.nominalTypeParameterSymbols(for: jsArraySymbol).first
        )
        let receiverType = try XCTUnwrap(sema.symbols.propertyType(for: jsArraySymbol))

        let constructor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsArrayFQName + [interner.intern("<init>")]).first { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .constructor,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.parameterTypes.isEmpty
                    && signature.returnType == receiverType
                    && signature.typeParameterSymbols == [typeParamSymbol]
                    && signature.classTypeParameterCount == 1
            },
            "JsArray<T>() constructor must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(constructor))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), "kk_js_array_create")
    }

    func testJsArrayConstructorResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsArray

        fun <T> makeArray(): JsArray<T> = JsArray<T>()
        fun stringArray(): JsArray<String> = JsArray<String>()
        """
        let (sema, interner) = try makeSema(source: source)

        for functionName in ["makeArray", "stringArray"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            guard case .classType = sema.types.kind(of: signature.returnType) else {
                return XCTFail("\(functionName) should return JsArray<T>, got \(sema.types.renderType(signature.returnType))")
            }
        }
    }

    private func arrayType(element: TypeID, sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let arrayFQName = ["kotlin", "Array"].map { interner.intern($0) }
        let arraySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: arrayFQName))
        return sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(element)],
            nullability: .nonNull
        )))
    }
}
