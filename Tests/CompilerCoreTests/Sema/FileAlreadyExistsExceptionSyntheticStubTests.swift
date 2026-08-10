#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-TYPE-002: Validates that `kotlin.io.FileAlreadyExistsException`
/// is registered as a synthetic class with the expected `Exception` supertype,
/// File-based constructor overloads, and routes to the shared
/// `__kk_throwable_new` runtime entry point.
@Suite
struct FileAlreadyExistsExceptionSyntheticStubTests {

    @Test
    func testFileAlreadyExistsExceptionSyntheticStubTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import java.io.File
            import kotlin.io.FileAlreadyExistsException

            fun build(file: File): FileAlreadyExistsException = FileAlreadyExistsException(file)

            fun buildWithOther(file: File, other: File?): FileAlreadyExistsException =
                FileAlreadyExistsException(file, other)

            fun buildWithReason(file: File, other: File?, reason: String?): FileAlreadyExistsException =
                FileAlreadyExistsException(file, other, reason)

            fun catchAsException(file: File): String =
                try { throw FileAlreadyExistsException(file) }
                catch (e: Exception) { e.message ?: "caught" }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testFileAlreadyExistsExceptionSurfaceIsRegistered ===
            do {

                let exceptionFQName = ["kotlin", "io", "FileAlreadyExistsException"].map { interner.intern($0) }
                let exceptionSymbol = try #require(sema.symbols.lookup(fqName: exceptionFQName))
                #expect(sema.symbols.symbol(exceptionSymbol)?.kind == .class)

                // Inherits from kotlin.Exception so try/catch chains observe the parent type.
                let rootExceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
                let rootExceptionSymbol = try #require(sema.symbols.lookup(fqName: rootExceptionFQName))
                #expect(sema.symbols.directSupertypes(for: exceptionSymbol).contains(rootExceptionSymbol))

                // The synthetic class type round-trips through propertyType for downstream lookups.
                let exceptionType = sema.types.make(.classType(ClassType(
                    classSymbol: exceptionSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(sema.symbols.propertyType(for: exceptionSymbol) == exceptionType)

                // Sanity-check the parent package wiring.
                let kotlinIOPkg = ["kotlin", "io"].map { interner.intern($0) }
                let kotlinIOPkgSymbol = try #require(sema.symbols.lookup(fqName: kotlinIOPkg))
                #expect(sema.symbols.parentSymbol(for: exceptionSymbol) == kotlinIOPkgSymbol)

                // All three constructor overloads land on java.io.File parameters and reuse
                // the shared throwable runtime entry point.
                let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
                let fileSymbol = try #require(sema.symbols.lookup(fqName: fileFQName))
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

                let constructorFQName = exceptionFQName + [interner.intern("<init>")]
                let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
                    sema.symbols.symbol($0)?.kind == .constructor
                }
                let expected: [[TypeID]] = [
                    [fileType],
                    [fileType, nullableFileType],
                    [fileType, nullableFileType, nullableStringType],
                ]
                for parameterTypes in expected {
                    let constructor = try #require(constructors.first {
                        sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
                    })
                    #expect(sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType)
                    #expect(sema.symbols.externalLinkName(for: constructor) == "__kk_throwable_new")
                }
            }

            // Source compiled for testFileAlreadyExistsExceptionResolvesInSource
            _ = diagnosticsForPath(paths[0], in: ctx)
        }
    }

}
#endif
