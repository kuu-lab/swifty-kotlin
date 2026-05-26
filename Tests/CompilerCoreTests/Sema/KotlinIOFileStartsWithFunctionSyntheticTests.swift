@testable import CompilerCore
import XCTest

final class KotlinIOFileStartsWithFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.startsWith surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileStartsWithFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("startsWith"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let fileOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [fileType]
                && signature.returnType == sema.types.booleanType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: fileOverload), "kk_file_startsWith_file")

        let stringOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == sema.types.booleanType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: stringOverload), "kk_file_startsWith_string")
    }

    func testFileStartsWithFunctionsResolveInSource() throws {
        let source = """
        import java.io.File
        import kotlin.io.startsWith

        fun withFile(file: File, other: File): Boolean = file.startsWith(other)
        fun withString(file: File): Boolean = file.startsWith("/tmp")
        """

        _ = try makeSema(source: source)
    }
}
