@testable import CompilerCore
import RuntimeABI
import XCTest

final class InputStreamReadBytesFunctionTests: XCTestCase {

    func testInputStreamReadBytesResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAll(file: File) {
            val stream = file.inputStream()
            val result = stream.readBytes()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testBufferedInputStreamReadBytesResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.BufferedInputStream
        import java.io.File

        fun loadAll(file: File) {
            val buffered: BufferedInputStream = file.inputStream().buffered()
            val result = buffered.readBytes()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected BufferedInputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testInputStreamReadBytesInsideUseBlock() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAll(file: File) {
            val result = file.inputStream().use { stream ->
                stream.readBytes()
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected InputStream.use { it.readBytes() } to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testInputStreamReadBytesSignatureAndRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let interner = ctx.interner
        let sema = try XCTUnwrap(ctx.sema)
        let symbols = sema.symbols
        let types = sema.types

        let inputStreamSymbol = try XCTUnwrap(
            symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
        )
        let inputStreamType = types.make(
            .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
        )
        let listSymbol = try XCTUnwrap(
            symbols.lookup(fqName: ["kotlin", "collections", "List"].map(interner.intern))
        )
        let listOfIntType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(types.intType)],
            nullability: .nonNull
        )))

        let candidates = symbols.lookupAll(
            fqName: ["java", "io", "InputStream", "readBytes"].map(interner.intern)
        )
        let readBytes = try XCTUnwrap(candidates.first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.parameterTypes.isEmpty
        })

        XCTAssertEqual(
            symbols.externalLinkName(for: readBytes),
            "kk_input_stream_readAllBytes"
        )

        let signature = try XCTUnwrap(symbols.functionSignature(for: readBytes))
        XCTAssertEqual(signature.returnType, listOfIntType)
        XCTAssertEqual(signature.receiverType, inputStreamType)
        XCTAssertTrue(signature.valueParameterIsVararg.allSatisfy { !$0 })
        XCTAssertTrue(signature.valueParameterHasDefaultValues.allSatisfy { !$0 })
    }

    func testRuntimeABISpecRegistersReadAllBytes() throws {
        let spec = RuntimeABISpec.fileIOFunctions.first { $0.name == "kk_input_stream_readAllBytes" }
        let unwrapped = try XCTUnwrap(spec)
        XCTAssertEqual(unwrapped.parameters.count, 2)
        XCTAssertEqual(unwrapped.parameters[0].name, "streamRaw")
        XCTAssertEqual(unwrapped.parameters[0].type, .intptr)
        XCTAssertEqual(unwrapped.parameters[1].name, "outThrown")
        XCTAssertEqual(unwrapped.parameters[1].type, .nullableIntptrPointer)
        XCTAssertEqual(unwrapped.returnType, .intptr)
        XCTAssertEqual(unwrapped.section, "FileIO")
    }
}
