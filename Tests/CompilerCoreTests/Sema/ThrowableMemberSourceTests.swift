@testable import CompilerCore
import Testing

/// KSP-654: `Throwable` members are declared in bundled Kotlin source
/// (`Stdlib/kotlin/Throwable.kt`) instead of synthetic stubs, so they carry no
/// `kk_*` external link name of their own.
@Suite
struct ThrowableMemberSourceTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Throwable surface to resolve cleanly, got: \(diagnostics)")
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testMessageAndCauseAreSourceDeclaredMembers() throws {
        let (sema, interner) = try makeSema()
        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try #require(sema.symbols.lookup(fqName: throwableFQName))
        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))

        let message = try #require(sema.symbols.lookupAll(
            fqName: throwableFQName + [interner.intern("message")]
        ).first { sema.symbols.symbol($0)?.kind == .property })
        #expect(sema.symbols.propertyType(for: message) == sema.types.makeNullable(sema.types.stringType))
        #expect(sema.symbols.externalLinkName(for: message) == nil)

        let cause = try #require(sema.symbols.lookupAll(
            fqName: throwableFQName + [interner.intern("cause")]
        ).first { sema.symbols.symbol($0)?.kind == .property })
        #expect(sema.symbols.propertyType(for: cause) == nullableThrowableType)
        #expect(sema.symbols.externalLinkName(for: cause) == nil)
    }

    @Test
    func testSuppressedExceptionsRootExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinPackage = ["kotlin"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let throwableSymbol = try #require(sema.symbols.lookup(
            fqName: kotlinPackage + [interner.intern("Throwable")]
        ))
        let listSymbol = try #require(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("List")]
        ))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let propertySymbol = try #require(
            sema.symbols.lookupAll(
                fqName: kotlinPackage + [interner.intern("suppressedExceptions")]
            ).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) == throwableType
            },
            "Expected kotlin.Throwable.suppressedExceptions root extension property"
        )

        let propertyType = try #require(sema.symbols.propertyType(for: propertySymbol))
        guard case let .classType(listType) = sema.types.kind(of: propertyType) else {
            Issue.record("Expected suppressedExceptions to be List<Throwable>")
            return
        }
        #expect(listType.classSymbol == listSymbol)
        switch listType.args.first {
        case let .invariant(element), let .out(element), let .in(element):
            #expect(element == throwableType)
        default:
            Issue.record("Expected suppressedExceptions element type argument")
        }
        #expect(sema.symbols.externalLinkName(for: propertySymbol) == nil)
    }

    @Test
    func testSuppressedExceptionsCanBeAssignedToListOfThrowable() throws {
        let source = """
        fun sample(e: Throwable) {
            val suppressed: List<Throwable> = e.suppressedExceptions
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        #expect(sema.symbols.functionSignature(for: sampleSymbol) != nil)
    }

    @Test
    func testMemberSurfaceTypeChecksOnSubclassReceivers() throws {
        let source = """
        fun sample(e: IllegalStateException): Int {
            val text: String? = e.message
            val root: Throwable? = e.cause
            e.addSuppressed(IllegalArgumentException("x"))
            e.initCause(root)
            return e.getSuppressed().size + e.suppressedExceptions.size + (if (text == null) 0 else 1)
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        #expect(sema.symbols.functionSignature(for: sampleSymbol)?.returnType == sema.types.intType)
    }
}
