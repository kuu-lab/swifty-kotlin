#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-619: Validates that the `kotlin.io` filesystem exception hierarchy comes
/// from the bundled Kotlin source (`Stdlib/kotlin/io/FileSystemException.kt`)
/// rather than synthetic stubs: `FileSystemException` derives from
/// `kotlin.Exception`, the concrete exceptions derive from it, and every
/// constructor arity binds to its own runtime storage entry point.
@Suite
struct FileSystemExceptionStdlibTests {
    private static let fixture = SemaFixture(surface: "FileSystemException", diagnostics: .unchecked)

    private func sharedSema(
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared(sourceLocation: sourceLocation)
    }

    private func makeSema(
        source: String = "fun noop() {}",
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source, sourceLocation: sourceLocation)
    }

    private func classSymbol(
        _ fqName: [String],
        _ sema: SemaModule,
        _ interner: StringInterner
    ) throws -> SymbolID {
        let symbol = try #require(sema.symbols.lookup(fqName: fqName.map { interner.intern($0) }))
        #expect(sema.symbols.symbol(symbol)?.kind == .class)
        return symbol
    }

    private func expectConstructors(
        of exceptionSymbol: SymbolID,
        fqName: [String],
        bridges: [SemaRuntimeFunction],
        sema: SemaModule,
        interner: StringInterner
    ) throws {
        let fileSymbol = try classSymbol(["java", "io", "File"], sema, interner)
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableFileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nullable
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorFQName = fqName.map { interner.intern($0) } + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expectedParameterTypes: [[TypeID]] = [
            [fileType],
            [fileType, nullableFileType],
            [fileType, nullableFileType, nullableStringType],
        ]
        #expect(bridges.count == expectedParameterTypes.count)
        for (parameterTypes, bridge) in zip(expectedParameterTypes, bridges) {
            let linkName = runtimeABIName(bridge)
            let constructor = try #require(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            #expect(sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType)
            #expect(sema.symbols.externalLinkName(for: constructor) == linkName)
        }
    }

    @Test func testHierarchyIsSourceBacked() throws {
        let (sema, interner) = try sharedSema()

        let exceptionSymbol = try classSymbol(["kotlin", "Exception"], sema, interner)
        let fileSystemSymbol = try classSymbol(["kotlin", "io", "FileSystemException"], sema, interner)
        #expect(sema.symbols.directSupertypes(for: fileSystemSymbol).contains(exceptionSymbol))

        for name in ["FileAlreadyExistsException", "AccessDeniedException", "NoSuchFileException"] {
            let symbol = try classSymbol(["kotlin", "io", name], sema, interner)
            #expect(sema.symbols.directSupertypes(for: symbol).contains(fileSystemSymbol))
            #expect(!sema.symbols.directSupertypes(for: symbol).contains(exceptionSymbol))
        }
    }

    @Test func testConstructorsBindToRuntimeStorage() throws {
        let (sema, interner) = try sharedSema()

        let cases: [([String], [SemaRuntimeFunction])] = [
            (["kotlin", "io", "FileSystemException"], [.fileSystemExceptionNewFile, .fileSystemExceptionNewFileOther, .fileSystemExceptionNewFileOtherReason]),
            (["kotlin", "io", "FileAlreadyExistsException"], [.fileAlreadyExistsExceptionNewFile, .fileAlreadyExistsExceptionNewFileOther, .fileAlreadyExistsExceptionNewFileOtherReason]),
            (["kotlin", "io", "AccessDeniedException"], [.accessDeniedExceptionNewFile, .accessDeniedExceptionNewFileOther, .accessDeniedExceptionNewFileOtherReason]),
            (["kotlin", "io", "NoSuchFileException"], [.noSuchFileExceptionNewFile, .noSuchFileExceptionNewFileOther, .noSuchFileExceptionNewFileOtherReason]),
        ]
        for (fqName, bridges) in cases {
            let symbol = try classSymbol(fqName, sema, interner)
            try expectConstructors(
                of: symbol,
                fqName: fqName,
                bridges: bridges,
                sema: sema,
                interner: interner
            )
        }
    }

    @Test func testResolvesInSource() throws {
        _ = try makeSema(source: """
        import java.io.File
        import kotlin.io.AccessDeniedException
        import kotlin.io.FileAlreadyExistsException
        import kotlin.io.FileSystemException

        fun build(file: File): FileAlreadyExistsException = FileAlreadyExistsException(file)

        fun buildWithOther(file: File, other: File?): FileAlreadyExistsException =
            FileAlreadyExistsException(file, other)

        fun buildWithReason(file: File, other: File?, reason: String?): AccessDeniedException =
            AccessDeniedException(file, other, reason)

        fun properties(e: FileSystemException): String =
            "${e.file.path}|${e.other?.path}|${e.reason}"

        fun catchAsBase(file: File): String =
            try { throw AccessDeniedException(file) }
            catch (e: FileSystemException) { e.message ?: "caught" }
        """)
    }
}
#endif
