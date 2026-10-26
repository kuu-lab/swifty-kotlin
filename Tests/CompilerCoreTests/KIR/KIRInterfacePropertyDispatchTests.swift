@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    @Test
    func setterSlotsReuseCachedGetterEligibilityAndOrdering() throws {
        let source = """
        interface SetterCacheProbe {
            val readOnly: Int
            var alpha: Int
            var excluded: Int
            var zeta: Int
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let interfaceName = [ctx.interner.intern("SetterCacheProbe")]
            let interfaceSymbol = try #require(sema.symbols.lookup(fqName: interfaceName))
            let alpha = try #require(sema.symbols.lookup(fqName: interfaceName + [ctx.interner.intern("alpha")]))
            let readOnly = try #require(sema.symbols.lookup(fqName: interfaceName + [ctx.interner.intern("readOnly")]))
            let excluded = try #require(sema.symbols.lookup(fqName: interfaceName + [ctx.interner.intern("excluded")]))
            let zeta = try #require(sema.symbols.lookup(fqName: interfaceName + [ctx.interner.intern("zeta")]))

            // An externally bridged mutable property has no getter slot and
            // therefore must not acquire a setter slot either.
            sema.symbols.setExternalLinkName("__kk_setter_cache_excluded", for: excluded)

            let cache = KIRNominalDispatchCache()
            let getterSlots = cache.interfacePropertyGetterSlots(
                for: interfaceSymbol,
                sema: sema,
                interner: ctx.interner
            )
            #expect(getterSlots.map { ctx.interner.resolve($0.propertyName) } == ["alpha", "readOnly", "zeta"])

            let setterSlots = cache.interfacePropertySetterSlots(
                for: interfaceSymbol,
                sema: sema,
                interner: ctx.interner
            )
            #expect(setterSlots.map { ctx.interner.resolve($0.propertyName) } == ["alpha", "zeta"])
            let firstSetterSlot = (getterSlots.map(\.slot).max() ?? -1) + 1
            #expect(setterSlots.map(\.slot) == [firstSetterSlot, firstSetterSlot + 1])

            #expect(cache.interfacePropertySetterSlot(
                for: alpha, in: interfaceSymbol, sema: sema, interner: ctx.interner
            ) == firstSetterSlot)
            #expect(cache.interfacePropertySetterSlot(
                for: zeta, in: interfaceSymbol, sema: sema, interner: ctx.interner
            ) == firstSetterSlot + 1)
            #expect(cache.interfacePropertySetterSlot(
                for: readOnly, in: interfaceSymbol, sema: sema, interner: ctx.interner
            ) == nil)
            #expect(cache.interfacePropertySetterSlot(
                for: excluded, in: interfaceSymbol, sema: sema, interner: ctx.interner
            ) == nil)

            // Lowering's sema is immutable. Changing it here proves that
            // repeated cache lookups reuse the original table and property map.
            sema.symbols.setExternalLinkName("__kk_setter_cache_now_excluded", for: alpha)
            let cachedSetterSlots = cache.interfacePropertySetterSlots(
                for: interfaceSymbol,
                sema: sema,
                interner: ctx.interner
            )
            #expect(cachedSetterSlots.map(\.slot) == setterSlots.map(\.slot))
            #expect(cache.interfacePropertySetterSlot(
                for: alpha, in: interfaceSymbol, sema: sema, interner: ctx.interner
            ) == firstSetterSlot)
        }
    }

    @Test
    func emptyInterfaceSetterTableCanBeRequestedRepeatedly() throws {
        try withTemporaryFile(contents: "interface EmptySetterTable {}\n") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let interfaceSymbol = try #require(
                sema.symbols.lookup(fqName: [ctx.interner.intern("EmptySetterTable")])
            )
            let cache = KIRNominalDispatchCache()

            #expect(cache.interfacePropertySetterSlots(
                for: interfaceSymbol, sema: sema, interner: ctx.interner
            ).isEmpty)
            #expect(cache.interfacePropertySetterSlots(
                for: interfaceSymbol, sema: sema, interner: ctx.interner
            ).isEmpty)
        }
    }
}
