@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-029: Validates that `isNotBlank` resolves through Sema for
/// both `String` and `CharSequence` receivers, returning a non-null `Boolean`.
///
/// The String receiver lowers to `kk_string_isNotBlank_flat`; the CharSequence
/// compatibility overload still uses `kk_string_isNotBlank`.
final class StringIsNotBlankFunctionTests: XCTestCase {
    func testIsNotBlankFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stringHasContent(value: String): Boolean {
            return value.isNotBlank()
        }

        fun charSequenceHasContent(value: CharSequence): Boolean {
            return value.isNotBlank()
        }

        fun literalHasContent(): Boolean {
            return "hello".isNotBlank()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isNotBlank to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIsNotBlankStringAndCharSequenceExtensionsHaveRuntimeLinks() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "isNotBlank"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        let stringSymbol = try XCTUnwrap(
            symbols.first {
                sema.symbols.functionSignature(for: $0)?.receiverType == sema.types.stringType
            },
            "Expected kotlin.text.isNotBlank(String receiver) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: stringSymbol),
            "kk_string_isNotBlank_flat",
            "Expected String.isNotBlank extension to link to kk_string_isNotBlank_flat"
        )

        let charSequenceSymbolID = try XCTUnwrap(sema.types.charSequenceInterfaceSymbol)
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbolID,
            args: [],
            nullability: .nonNull
        )))
        let charSequenceSymbol = try XCTUnwrap(
            symbols.first {
                sema.symbols.functionSignature(for: $0)?.receiverType == charSequenceType
            },
            "Expected kotlin.text.isNotBlank(CharSequence receiver) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: charSequenceSymbol),
            "kk_string_isNotBlank",
            "Expected CharSequence.isNotBlank extension to keep kk_string_isNotBlank"
        )
    }
}
