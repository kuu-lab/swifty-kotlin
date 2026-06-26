@testable import CompilerCore
import XCTest

// STDLIB-CINTEROP-FN-039: kotlinx.cinterop.typeOf<T>() stub registration
final class CinteropTypeOfSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected cinterop typeOf surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testCinteropTypeOfIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let typeOfSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("typeOf")]).first,
            "Expected kotlinx.cinterop.typeOf to be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(typeOfSymbol))
        XCTAssertEqual(info.kind, .function)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.inlineFunction))

        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: typeOfSymbol))
        XCTAssertTrue(sig.parameterTypes.isEmpty)
        XCTAssertEqual(sig.reifiedTypeParameterIndices, [0])
        XCTAssertNil(sig.receiverType)

        let reflectPkg = ["kotlin", "reflect"].map { interner.intern($0) }
        let kTypeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectPkg + [interner.intern("KType")])
        )
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sig.returnType, expectedReturnType)
    }

    func testCinteropTypeOfResolvesInSource() throws {
        let source = """
        import kotlinx.cinterop.typeOf
        import kotlin.reflect.KType

        fun getStringType(): KType = typeOf<String>()
        """
        let (_, _) = try makeSema(source: source)
    }
}
