@testable import CompilerCore
import XCTest

final class KotlinIOFileToRelativeStringFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.toRelativeString surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileToRelativeStringFunctionIsRegistered() throws {
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
            interner.intern("toRelativeString"),
        ]

        let functionSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [fileType]
                && signature.returnType == sema.types.stringType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionSymbol), "kk_file_toRelativeString")
    }

    func testFileToRelativeStringFunctionResolvesInSource() throws {
        let source = """
        import java.io.File
        import kotlin.io.toRelativeString

        fun relative(file: File, base: File): String = file.toRelativeString(base)
        """

        _ = try makeSema(source: source)
    }
}
