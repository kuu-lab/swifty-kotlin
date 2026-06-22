@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-050: Validates that `CharSequence.removePrefix(prefix)` resolves
/// through Sema for `String` receivers across several invocation shapes (variable,
/// literal, chained call, and conditional contexts). The synthetic stub is
/// registered in `HeaderHelpers+SyntheticStringStubs.swift` and lowered to the
/// flattened runtime helper `kk_string_removePrefix_flat` defined in
/// `RuntimeStringStdlib.swift`.
final class StringRemovePrefixFunctionTests: XCTestCase {
    func testRemovePrefixResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripScheme(s: String): String {
            return s.removePrefix("https://")
        }

        fun stripFromLiteral(): String {
            return "HelloWorld".removePrefix("Hello")
        }

        fun stripFromExpression(value: Int): String {
            return value.toString().removePrefix("0")
        }

        fun stripInBranch(s: String): String {
            return if (s.removePrefix("foo").isEmpty()) "empty" else s.removePrefix("foo")
        }

        fun stripChained(s: String): String {
            return s.removePrefix("a").removePrefix("b")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected removePrefix to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// Confirms the synthetic stubs for `String`-typed remove helpers are registered
    /// with flattened runtime link names and `String -> String` shapes.
    func testStringRemoveHelpersResolveToFlattenedRuntimeLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            let charSequenceSymbolID = try XCTUnwrap(sema.types.charSequenceInterfaceSymbol)
            let charSequenceType = sema.types.make(.classType(ClassType(
                classSymbol: charSequenceSymbolID,
                args: [],
                nullability: .nonNull
            )))

            func assertStringHelper(
                _ name: String,
                parameterCount: Int,
                externalLinkName: String,
                receiverType: TypeID? = nil,
                parameterType: TypeID? = nil,
                file: StaticString = #filePath,
                line: UInt = #line
            ) throws {
                let expectedReceiverType = receiverType ?? sema.types.stringType
                let expectedParameterType = parameterType ?? sema.types.stringType
                let fq = ["kotlin", "text", name].map { ctx.interner.intern($0) }
                let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == expectedReceiverType
                        && signature.parameterTypes == Array(repeating: expectedParameterType, count: parameterCount)
                }, file: file, line: line)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: symbol),
                    externalLinkName,
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    sema.symbols.functionSignature(for: symbol)?.returnType,
                    sema.types.stringType,
                    "String.\(name) should return String",
                    file: file,
                    line: line
                )
            }

            try assertStringHelper(
                "removePrefix",
                parameterCount: 1,
                externalLinkName: "kk_string_removePrefix_flat"
            )
            try assertStringHelper(
                "removeSuffix",
                parameterCount: 1,
                externalLinkName: "kk_string_removeSuffix_flat"
            )
            try assertStringHelper(
                "removeSurrounding",
                parameterCount: 1,
                externalLinkName: "kk_string_removeSurrounding_flat"
            )
            try assertStringHelper(
                "removeSurrounding",
                parameterCount: 2,
                externalLinkName: "kk_string_removeSurrounding_pair_flat"
            )
            try assertStringHelper(
                "removePrefix",
                parameterCount: 1,
                externalLinkName: "kk_string_removePrefix_flat",
                receiverType: charSequenceType,
                parameterType: charSequenceType
            )
            try assertStringHelper(
                "removeSuffix",
                parameterCount: 1,
                externalLinkName: "kk_string_removeSuffix_flat",
                receiverType: charSequenceType,
                parameterType: charSequenceType
            )
            try assertStringHelper(
                "removeSurrounding",
                parameterCount: 1,
                externalLinkName: "kk_string_removeSurrounding_flat",
                receiverType: charSequenceType,
                parameterType: charSequenceType
            )
            try assertStringHelper(
                "removeSurrounding",
                parameterCount: 2,
                externalLinkName: "kk_string_removeSurrounding_pair_flat",
                receiverType: charSequenceType,
                parameterType: charSequenceType
            )
        }
    }
}
