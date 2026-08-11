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
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        let pair = try makeSema()
        Self._sharedSema = pair
        return pair
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
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
        linkNamePrefix: String,
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
        let expected: [([TypeID], String)] = [
            ([fileType], "\(linkNamePrefix)_new_file"),
            ([fileType, nullableFileType], "\(linkNamePrefix)_new_file_other"),
            ([fileType, nullableFileType, nullableStringType], "\(linkNamePrefix)_new_file_other_reason"),
        ]
        for (parameterTypes, linkName) in expected {
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

        let cases: [([String], String)] = [
            (["kotlin", "io", "FileSystemException"], "__kk_file_system_exception"),
            (["kotlin", "io", "FileAlreadyExistsException"], "__kk_file_already_exists_exception"),
            (["kotlin", "io", "AccessDeniedException"], "__kk_access_denied_exception"),
            (["kotlin", "io", "NoSuchFileException"], "__kk_no_such_file_exception"),
        ]
        for (fqName, linkNamePrefix) in cases {
            let symbol = try classSymbol(fqName, sema, interner)
            try expectConstructors(
                of: symbol,
                fqName: fqName,
                linkNamePrefix: linkNamePrefix,
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
