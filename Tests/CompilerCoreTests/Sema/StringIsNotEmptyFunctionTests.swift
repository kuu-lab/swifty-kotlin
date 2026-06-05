@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-030: Validates that `isNotEmpty` resolves through Sema for
/// `String` and `CharSequence` receivers, returning a non-null `Boolean`.
///
/// The String receiver lowers to `kk_string_isNotEmpty_flat`; the CharSequence
/// compatibility overload still uses `kk_string_isNotEmpty`.
final class StringIsNotEmptyFunctionTests: XCTestCase {
    func testIsNotEmptyFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stringHasContent(value: String): Boolean {
            return value.isNotEmpty()
        }

        fun charSequenceHasContent(value: CharSequence): Boolean {
            return value.isNotEmpty()
        }

        fun literalHasContent(): Boolean {
            return "hello".isNotEmpty()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isNotEmpty to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIsNotEmptyStringAndCharSequenceExtensionsHaveRuntimeLinks() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "isNotEmpty"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        let stringSymbol = try XCTUnwrap(
            symbols.first {
                sema.symbols.functionSignature(for: $0)?.receiverType == sema.types.stringType
            },
            "Expected kotlin.text.isNotEmpty(String receiver) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: stringSymbol),
            "kk_string_isNotEmpty_flat",
            "Expected String.isNotEmpty extension to link to kk_string_isNotEmpty_flat"
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
            "Expected kotlin.text.isNotEmpty(CharSequence receiver) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: charSequenceSymbol),
            "kk_string_isNotEmpty",
            "Expected CharSequence.isNotEmpty extension to keep kk_string_isNotEmpty"
        )
    }
}
