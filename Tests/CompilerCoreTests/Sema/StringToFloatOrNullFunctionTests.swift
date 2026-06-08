@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-098: `fun String.toFloatOrNull(): Float?` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toFloatOrNull` links to the
///   runtime symbol `kk_string_toFloatOrNull` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Float?`.
final class StringToFloatOrNullFunctionTests: XCTestCase {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func externalLinks(for member: String, sema: SemaModule, interner: StringInterner) -> Set<String> {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    func testToFloatOrNullStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertEqual(
                externalLink(for: "toFloatOrNull", sema: sema, interner: ctx.interner),
                "kk_string_toFloatOrNull",
                "String.toFloatOrNull should link to kk_string_toFloatOrNull"
            )

            let links = externalLinks(for: "toFloatOrNull", sema: sema, interner: ctx.interner)
            XCTAssertTrue(
                links.contains("kk_string_toFloatOrNull"),
                "lookupAll for toFloatOrNull must include kk_string_toFloatOrNull; got: \(links)"
            )
        }
    }

    func testToFloatOrNullResolvesOnStringReceiver() throws {
        let source = """
        fun parse(raw: String): Float? {
            return raw.toFloatOrNull()
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
                "Expected String.toFloatOrNull to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    func testToFloatOrNullReturnsNullableFloat() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "toFloatOrNull"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.stringType && sig.parameterTypes.isEmpty
                }
            )
            let returnType = try XCTUnwrap(sema.symbols.functionSignature(for: symbol)?.returnType)
            XCTAssertEqual(
                returnType,
                sema.types.make(.primitive(.float, .nullable)),
                "String.toFloatOrNull() should return Float?"
            )
        }
    }

    func testToFloatOrNullInBranchContext() throws {
        let source = """
        fun safeParse(raw: String): Float {
            return raw.toFloatOrNull() ?: 0.0f
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Elvis operator over toFloatOrNull should type-check without errors"
            )
        }
    }
}
