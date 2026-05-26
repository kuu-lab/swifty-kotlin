@testable import CompilerCore
import XCTest

final class KotlinIOReaderReadTextFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Reader.readText surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testReaderReadTextFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let readerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("Reader"),
        ]))
        let readerType = sema.types.make(.classType(ClassType(
            classSymbol: readerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("readText"),
        ]

        let functionSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == readerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.stringType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionSymbol), "kk_reader_readText")
    }

    func testReaderReadTextFunctionResolvesInSource() throws {
        let source = """
        import java.io.Reader
        import kotlin.io.readText

        fun read(reader: Reader): String = reader.readText()
        """

        _ = try makeSema(source: source)
    }
}
