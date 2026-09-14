#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1260: the complete `Debugging` surface is source-backed and retains
/// its exact Kotlin 2.3.10 member ownership, mutability, and types.
@Suite
struct NativeDebuggingSourceAPITests {
    @Test
    func testDebuggingSourceBackedSurfaceHasExactTypesAndOwnership() throws {
        let source = """
        @file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

        import kotlin.native.runtime.Debugging

        fun probe(): Boolean {
            val runnable: Boolean = Debugging.isThreadStateRunnable
            Debugging.forceCheckedShutdown = !Debugging.forceCheckedShutdown
            val dumped: Boolean = Debugging.dumpMemory(2L)
            return runnable && dumped
        }
        """

        var result: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let objectFQName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
        let objectID = try #require(sema.symbols.lookup(fqName: objectFQName))
        let object = try #require(sema.symbols.symbol(objectID))
        #expect(object.kind == .object)
        #expect(sema.symbols.isSourceBackedSymbol(objectID))
        #expect(!object.flags.contains(.synthetic))
        #expect(
            hasOptInAnnotation(on: objectID, markerContaining: "NativeRuntimeApi", sema: sema),
            "Debugging should carry @NativeRuntimeApi annotation"
        )

        let expectedProperties: [(String, TypeID, Bool)] = [
            ("isThreadStateRunnable", sema.types.booleanType, false),
            ("forceCheckedShutdown", sema.types.booleanType, true),
        ]
        for (name, expectedType, isMutable) in expectedProperties {
            let propertyFQName = objectFQName + [interner.intern(name)]
            let propertyID = try #require(
                sema.symbols.lookup(fqName: propertyFQName),
                "Debugging.\(name) must be source-backed"
            )
            let property = try #require(sema.symbols.symbol(propertyID))
            #expect(property.kind == .property)
            #expect(sema.symbols.isSourceBackedSymbol(propertyID))
            #expect(!property.flags.contains(.synthetic))
            #expect(property.flags.contains(.mutable) == isMutable)
            #expect(sema.symbols.propertyType(for: propertyID) == expectedType)
        }

        let functionFQName = objectFQName + [interner.intern("dumpMemory")]
        let functionID = try #require(
            sema.symbols.lookupAll(fqName: functionFQName).first,
            "Debugging.dumpMemory must be source-backed"
        )
        let function = try #require(sema.symbols.symbol(functionID))
        let signature = try #require(sema.symbols.functionSignature(for: functionID))
        #expect(function.kind == .function)
        #expect(sema.symbols.isSourceBackedSymbol(functionID))
        #expect(!function.flags.contains(.synthetic))
        #expect(signature.parameterTypes == [sema.types.longType])
        #expect(signature.returnType == sema.types.booleanType)

        let expectedBridgeNames: Set<String> = [
            "__kk_debugging_is_thread_state_runnable",
            "__kk_debugging_force_checked_shutdown_get",
            "__kk_debugging_force_checked_shutdown_set",
            "__kk_debugging_dump_memory",
        ]
        let actualBridgeNames = Set(sema.symbols.allSymbols().compactMap {
            sema.symbols.externalLinkName(for: $0.id)
        })
        #expect(expectedBridgeNames.isSubset(of: actualBridgeNames))
    }

    private func hasOptInAnnotation(
        on symbol: SymbolID,
        markerContaining keyword: String,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.annotations(for: symbol).contains {
            $0.annotationFQName.lowercased().contains(keyword.lowercased())
        }
    }
}
#endif
