@testable import CompilerCore
import Testing

@Suite
struct KIRInterfacePropertyDispatchTests {
    @Test
    func continuationContextRetainsRuntimeFallbackGetterSlot() throws {
        try withTemporaryFile(contents: "import kotlin.coroutines.*\nfun read(c: Continuation<Int>): CoroutineContext = c.context\n") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let continuationName = ["kotlin", "coroutines", "Continuation"].map(ctx.interner.intern)
            let continuation = try #require(sema.symbols.lookup(fqName: continuationName))
            let slots = kirInterfacePropertyGetterSlots(interfaceSymbol: continuation, sema: sema, interner: ctx.interner)
            #expect(slots.map { ctx.interner.resolve($0.propertyName) } == ["context"])
            #expect(slots.map(\.slot) == [1])

            // Imported metadata can put the bridge on the accessor rather than the property.
            let context = try #require(sema.symbols.lookup(fqName: continuationName + [ctx.interner.intern("context")]))
            sema.symbols.setExternalLinkName("", for: context)
            let imported = kirInterfacePropertyGetterSlots(interfaceSymbol: continuation, sema: sema, interner: ctx.interner)
            #expect(imported.map(\.slot) == [1])
        }
    }

    @Test
    func runtimeBridgedPropertiesDoNotShiftImportedJobKeySlot() throws {
        try withTemporaryFile(contents: "import kotlinx.coroutines.*\nfun main() { println(NonCancellable.key) }\n") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let jobName = ["kotlinx", "coroutines", "Job"].map(ctx.interner.intern)
            let job = try #require(sema.symbols.lookup(fqName: jobName))
            let expected = kirInterfacePropertyGetterSlots(interfaceSymbol: job, sema: sema, interner: ctx.interner)
            #expect(expected.map { ctx.interner.resolve($0.propertyName) } == ["key"])

            for name in ["isActive", "isCompleted", "isCancelled"] {
                let property = try #require(sema.symbols.lookup(fqName: jobName + [ctx.interner.intern(name)]))
                sema.symbols.setExternalLinkName("", for: property)
            }
            let imported = kirInterfacePropertyGetterSlots(interfaceSymbol: job, sema: sema, interner: ctx.interner)
            #expect(imported.map { ctx.interner.resolve($0.propertyName) } == ["key"])
            #expect(imported.map(\.slot) == expected.map(\.slot))
        }
    }
}
