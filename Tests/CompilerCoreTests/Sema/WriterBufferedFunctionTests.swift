@testable import CompilerCore
import XCTest

/// Surface tests for `kotlin.io.Writer.buffered(bufferSize: Int = DEFAULT_BUFFER_SIZE): BufferedWriter`.
///
/// Verifies STDLIB-IO-FN-006 — the synthetic Sema stub registers both the
/// no-argument and bufferSize overloads, resolves them on `java.io.Writer`,
/// returns `java.io.BufferedWriter`, and binds them to the documented
/// `kk_writer_buffered_default` / `kk_writer_buffered` runtime symbols.
final class WriterBufferedFunctionTests: XCTestCase {
    func testWriterBufferedFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let writerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("Writer"),
        ]))
        let writerType = sema.types.make(.classType(ClassType(
            classSymbol: writerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let bufferedWriterSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("BufferedWriter"),
        ]))
        let bufferedWriterType = sema.types.make(.classType(ClassType(
            classSymbol: bufferedWriterSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("buffered"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == writerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == bufferedWriterType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_writer_buffered_default")

        let bufferSizeOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == writerType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == bufferedWriterType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: bufferSizeOverload), "kk_writer_buffered")
    }

    func testWriterBufferedFunctionsResolveInSource() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.Writer
        import kotlin.io.buffered

        fun defaultBuffered(writer: Writer): BufferedWriter = writer.buffered()
        fun sizedBuffered(writer: Writer): BufferedWriter = writer.buffered(1024)
        """

        _ = try makeSema(source: source)
    }

    func testBufferedWriterIsRecognizedAsWriterSubtype() throws {
        let (sema, interner) = try makeSema()
        let writerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("Writer"),
        ]))
        let bufferedWriterSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("BufferedWriter"),
        ]))
        let supertypes = sema.symbols.directSupertypes(for: bufferedWriterSymbol)
        XCTAssertTrue(
            supertypes.contains(writerSymbol),
            "BufferedWriter should declare Writer as a direct supertype so that Writer extensions resolve on BufferedWriter values."
        )
    }
}
