@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-073: Validates that `CharSequence.substring(startIndex, endIndex)`
/// resolves through Sema for String receivers across multiple call sites and
/// links to the runtime helper `kk_string_substring_flat` (see
/// `Sources/Runtime/RuntimeStringStdlib.swift`).
final class StringSubstringFunctionTests: XCTestCase {
    func testStringSubstringResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun headTwo(s: String): String {
            return s.substring(0, 2)
        }

        fun fromIndex(s: String): String {
            return s.substring(3)
        }

        fun substringOfLiteral(): String {
            return "hello world".substring(6, 11)
        }

        fun emptySliceOfLiteral(): String {
            return "abc".substring(1, 1)
        }

        fun substringInBranch(s: String, take: Boolean): String {
            return if (take) s.substring(0, 1) else s.substring(1)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.substring(...) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSubstringTwoArgOverloadResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "substring"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 2
                    && signature.parameterTypes.allSatisfy { $0 == sema.types.intType }
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            XCTAssertEqual(
                sema.symbols.functionSignature(for: symbol)?.returnType,
                sema.types.stringType,
                "String.substring(startIndex, endIndex) should return String"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_string_substring_flat")
    }

    func testSubstringOneArgOverloadResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "substring"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 1
                    && signature.parameterTypes[0] == sema.types.intType
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            XCTAssertEqual(
                sema.symbols.functionSignature(for: symbol)?.returnType,
                sema.types.stringType,
                "String.substring(startIndex) should return String"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_string_substring_flat")
    }

    func testSubSequenceOverloadResolvesToFlatRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "subSequence"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 2
                    && signature.parameterTypes.allSatisfy { $0 == sema.types.intType }
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            XCTAssertEqual(
                sema.symbols.functionSignature(for: symbol)?.returnType,
                sema.types.stringType,
                "String.subSequence(startIndex, endIndex) should return String"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_string_subSequence_flat")
    }
}
