#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-PROP-004: Validates that the synthetic `kotlin.io.File.isRooted`
/// extension property is registered with the `java.io.File` receiver and is
/// resolvable in Sema with a `Boolean` result type. The runtime link is
/// `kk_file_isRooted` (see `Sources/Runtime/RuntimeFileIO.swift`).
@Suite
struct FileIsRootedTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected File.isRooted to resolve cleanly, got: \(diagnostics)"
            )
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    /// The extension property symbol lives under `kotlin.io.isRooted` with
    /// `java.io.File` as its receiver type and `Boolean` as its return type.
    /// The accessor getter must share the same external link name so codegen
    /// can dispatch the property read through `kk_file_isRooted`.
    @Test func testFileIsRootedExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinIOPkg = ["kotlin", "io"].map { interner.intern($0) }
        let javaIOPkg = ["java", "io"].map { interner.intern($0) }
        let fileSymbol = try #require(sema.symbols.lookup(
            fqName: javaIOPkg + [interner.intern("File")]
        ))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        let propertySymbol = try #require(
            sema.symbols.lookupAll(fqName: kotlinIOPkg + [interner.intern("isRooted")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) == fileType
            },
            "Expected kotlin.io.File.isRooted extension property"
        )
        #expect(sema.symbols.propertyType(for: propertySymbol) == boolType)

        let getterSymbol = try #require(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        let signature = try #require(sema.symbols.functionSignature(for: getterSymbol))
        #expect(signature.receiverType == fileType)
        #expect(signature.returnType == boolType)
        #expect(signature.parameterTypes.isEmpty)
    }

    /// User code that reads `file.isRooted` should type-check without errors
    /// and the surrounding function should still infer `Boolean`. The branch
    /// usage mirrors typical stdlib call sites where `isRooted` gates further
    /// path manipulation.
    @Test func testFileIsRootedResolvesInSource() throws {
        let source = """
        import java.io.File

        fun checkRoot(file: File): Boolean {
            return file.isRooted
        }

        fun useInBranch(file: File): String {
            return if (file.isRooted) "abs" else "rel"
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let checkRootSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("checkRoot")]))
        let checkSignature = try #require(sema.symbols.functionSignature(for: checkRootSymbol))
        #expect(
            checkSignature.returnType == sema.types.make(.primitive(.boolean, .nonNull)),
            "checkRoot should still return Boolean once isRooted resolves"
        )

        let useInBranchSymbol = try #require(
            sema.symbols.lookup(fqName: [interner.intern("useInBranch")])
        )
        let branchSignature = try #require(sema.symbols.functionSignature(for: useInBranchSymbol))
        #expect(
            branchSignature.returnType == sema.types.stringType,
            "useInBranch should still return String once isRooted resolves"
        )
    }
}
#endif
