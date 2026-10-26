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

    /// `kirInterfacePropertyGetterSlots` must produce the same table whether a
    /// runtime bridge is recorded as the property's `externalLinkName` (the
    /// source-compiled stdlib shape) or only as a surviving `@KsSymbolName`
    /// annotation — precompiled-library metadata puts the link name on the
    /// getter accessor, leaving the property's own link name empty.
    ///
    /// `Job` can no longer model this mix: KUU-1386 bridged all of its
    /// properties (`key` included — `job.key` reads lower to the
    /// `__kkCoroutineElementKey` helper, which re-dispatches source objects
    /// through `Element.key`'s non-bridged slot, while `kk_job_key_get`
    /// covers raw handles and `super<Job>.key`), so the KUU-1087
    /// `NonCancellable.key` regression is reproduced on a synthetic
    /// interface instead.
    @Test
    func runtimeBridgedPropertiesDoNotShiftSourceBackedGetterSlot() throws {
        let source = """
        interface BridgedSlotProbe {
            val alpha: Int
            val beta: Int
            val gamma: Int
            val sourceBacked: Int
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let interfaceName = [ctx.interner.intern("BridgedSlotProbe")]
            let interfaceSymbol = try #require(sema.symbols.lookup(fqName: interfaceName))
            let bridged = try ["alpha", "beta", "gamma"].map { name in
                try #require(sema.symbols.lookup(fqName: interfaceName + [ctx.interner.intern(name)]))
            }

            // Source-compiled stdlib shape: `@KsSymbolName` leaves both the
            // annotation record and the resolved external link name on the
            // property (HeaderHelpers).
            for (index, property) in bridged.enumerated() {
                let linkName = "kk_bridged_slot_probe_\(index)"
                sema.symbols.setAnnotations(
                    [MetadataAnnotationRecord(
                        annotationFQName: "kotlin.internal.KsSymbolName",
                        arguments: [linkName]
                    )],
                    for: property
                )
                sema.symbols.setExternalLinkName(linkName, for: property)
            }
            let expected = kirInterfacePropertyGetterSlots(
                interfaceSymbol: interfaceSymbol, sema: sema, interner: ctx.interner
            )
            #expect(expected.map { ctx.interner.resolve($0.propertyName) } == ["sourceBacked"])

            // Imported-library shape: the bridge lives on the getter accessor,
            // so the property's own link name is empty — but the annotation
            // still marks it bridged and the layout must not change.
            for property in bridged {
                sema.symbols.setExternalLinkName("", for: property)
            }
            let imported = kirInterfacePropertyGetterSlots(
                interfaceSymbol: interfaceSymbol, sema: sema, interner: ctx.interner
            )
            #expect(imported.map { ctx.interner.resolve($0.propertyName) } == ["sourceBacked"])
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

    /// kt2477: a `private` member — whether on the superclass or on a
    /// sibling interface — never implements an interface property, so it
    /// must not be selected as the itable getter for `A.c`. The interface's
    /// own (possibly `private`) declaration remains the fallback for its own
    /// slot.
    @Test
    func privateMembersAreNotSelectedAsInterfacePropertyGetter() throws {
        let source = """
        interface Kt2477A {
            val c: Int
                get() = 1
        }

        interface Kt2477B {
            private val c: Int
                get() = 2
        }

        open class Kt2477C {
            private val c: Int = 3
        }

        class Kt2477D : Kt2477C(), Kt2477A, Kt2477B
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let cName = ctx.interner.intern("c")
            let aC = try #require(sema.symbols.lookup(
                fqName: [ctx.interner.intern("Kt2477A"), cName]
            ))
            let bC = try #require(sema.symbols.lookup(
                fqName: [ctx.interner.intern("Kt2477B"), cName]
            ))
            let dClass = try #require(sema.symbols.lookup(
                fqName: [ctx.interner.intern("Kt2477D")]
            ))

            #expect(
                kirFindOverridePropertyGetter(for: aC, in: dClass, sema: sema)
                    == SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: aC)
            )
            // The sibling interface's private slot keeps its own default.
            #expect(
                kirFindOverridePropertyGetter(for: bC, in: dClass, sema: sema)
                    == SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: bC)
            )
        }
    }

    /// kt2477 (method shape): the same name-only search used for interface
    /// methods must likewise skip `private` members on the class chain and
    /// on unrelated interfaces.
    @Test
    func privateMembersAreNotSelectedAsInterfaceMethodImplementation() throws {
        let source = """
        interface Kt2477MethodA {
            fun c(): Int = 1
        }

        interface Kt2477MethodB {
            private fun c(): Int = 2
        }

        open class Kt2477MethodC {
            private fun c(): Int = 3
        }

        class Kt2477MethodD : Kt2477MethodC(), Kt2477MethodA, Kt2477MethodB
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let cName = ctx.interner.intern("c")
            let aC = try #require(sema.symbols.lookup(
                fqName: [ctx.interner.intern("Kt2477MethodA"), cName]
            ))
            let bC = try #require(sema.symbols.lookup(
                fqName: [ctx.interner.intern("Kt2477MethodB"), cName]
            ))
            let dClass = try #require(sema.symbols.lookup(
                fqName: [ctx.interner.intern("Kt2477MethodD")]
            ))

            #expect(
                kirFindOverrideMethod(for: aC, in: dClass, sema: sema, interner: ctx.interner)
                    == aC
            )
            #expect(
                kirFindOverrideMethod(for: bC, in: dClass, sema: sema, interner: ctx.interner)
                    == bC
            )
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

    @Test
    func privateInterfacePropertyDoesNotAcquireGetterSlot() throws {
        let source = """
        interface PrivatePropProbe {
            val publicProp: String
            private val privateProp: String get() = "FAIL"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let interfaceSymbol = try #require(
                sema.symbols.lookup(fqName: [ctx.interner.intern("PrivatePropProbe")])
            )
            let slots = kirInterfacePropertyGetterSlots(interfaceSymbol: interfaceSymbol, sema: sema, interner: ctx.interner)
            #expect(slots.map { ctx.interner.resolve($0.propertyName) } == ["publicProp"])
        }
    }

    @Test
    func privateSuperclassPropertyDoesNotOverrideInterfaceProperty() throws {
        let source = """
        interface Iface {
            val c: String get() = "OK"
        }
        open class Base {
            private val c: String = "FAIL"
        }
        class Sub : Base(), Iface
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let ifaceProp = try #require(
                sema.symbols.lookup(fqName: [ctx.interner.intern("Iface"), ctx.interner.intern("c")])
            )
            let subSymbol = try #require(
                sema.symbols.lookup(fqName: [ctx.interner.intern("Sub")])
            )
            let overrideGetter = kirFindOverridePropertyGetter(
                for: ifaceProp,
                in: subSymbol,
                sema: sema
            )
            let ifaceGetter = sema.symbols.extensionPropertyGetterAccessor(for: ifaceProp)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: ifaceProp)
            #expect(overrideGetter == ifaceGetter)
        }
    }
}
