#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct DelegatedPropertyExtensionGetValueTests {
    @Test(arguments: [false, true])
    func reportedBoxCasesResolveGetValue(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }

        let sources = [
            """
            package kuu2133.memberProperty
            open class A {
                val a: String.() -> String = { this }
                val b: (String) -> String by this::a
            }
            class B {
                val b: (String) -> String by A()::a
            }
            class C : A() {
                val c: (String) -> String by ::a
            }
            fun box(): String = A().b("O") + B().b("K") + C().c("")
            """,
            """
            package kuu2133.extensionProperty
            val x: String.() -> String = { this }
            val String.y: String.() -> String
                get() = { this + this@y }
            val String.c: String.() -> String by String::y
            val String.d: (String) -> String by String::y
            fun box(): String = "2".c("1") + "4".d("3")
            """,
            """
            package kuu2133.finalProperty
            val impl = 123
            operator fun Any?.getValue(thisRef: Any?, property: Any?) =
                if (this == 123 && thisRef == null) "OK" else "Failed"
            val value: String by impl
            fun box(): String = value
            """,
            """
            package kuu2133.enumBound
            import kotlin.properties.ReadWriteProperty
            import kotlin.reflect.KProperty
            enum class Enumeration { OK }
            inline fun <reified T : Enum<T>> delegate() = object : ReadWriteProperty<Any?, T?> {
                override fun getValue(thisRef: Any?, property: KProperty<*>): T? = Enumeration.OK as T?
                override fun setValue(thisRef: Any?, property: KProperty<*>, value: T?) {}
            }
            class Klass {
                var enumeration: Enumeration? by delegate()
            }
            fun box(): String = Klass().enumeration.toString()
            """,
        ]
        let ctx = makeContextFromSources(sources, allowDefaultStdlibLibrary: useArtifact)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let hasErrors = ctx.diagnostics.hasError
        #expect(!hasErrors, "Unexpected diagnostics: \(errors.map { "\($0.code): \($0.message)" })")

        let sema = try #require(ctx.sema)
        let enumerationProperty = try #require(sema.symbols.lookup(
            fqName: ["kuu2133", "enumBound", "Klass", "enumeration"].map(ctx.interner.intern)
        ))
        let readWriteProperty = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "properties", "ReadWriteProperty"].map(ctx.interner.intern)
        ))
        let getValue = try #require(sema.symbols.delegateGetValueSymbol(for: enumerationProperty))
        let setValue = try #require(sema.symbols.delegateSetValueSymbol(for: enumerationProperty))
        let getValueOwner = try #require(sema.symbols.parentSymbol(for: getValue))
        let setValueOwner = try #require(sema.symbols.parentSymbol(for: setValue))
        #expect(getValueOwner == readWriteProperty || sema.types.isNominalSubtypeSymbol(getValueOwner, of: readWriteProperty))
        #expect(setValueOwner == readWriteProperty || sema.types.isNominalSubtypeSymbol(setValueOwner, of: readWriteProperty))
    }

    // KUU-3206: an extension getValue/setValue declared *after* the delegated
    // property still resolves. Its expression body leaves the header return
    // type as the `Any` placeholder until inference runs on demand; the
    // convention's expected-type probe must not reject it early.
    @Test(arguments: [false, true])
    func forwardDeclaredExtensionGetValueResolves(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }

        let source = """
        package kuu3206.forwardDeclared

        class C {
            val impl = 123
            val s: String by impl
            var t: String by impl
        }
        operator fun Any?.getValue(thisRef: Any?, property: Any?) = "OK"
        operator fun Any?.setValue(thisRef: Any?, property: Any?, value: String) {}

        fun local(): String {
            val impl = 7
            val s: String by impl
            return s
        }

        fun box(): String = C().s + C().t + local()
        """

        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: useArtifact)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { "\($0.code): \($0.message)" })")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let anyGetValue = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kuu3206"), interner.intern("forwardDeclared"), interner.intern("getValue"),
        ]))
        let anySetValue = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kuu3206"), interner.intern("forwardDeclared"), interner.intern("setValue"),
        ]))

        let classChildren = sema.symbols.children(ofFQName: [
            interner.intern("kuu3206"), interner.intern("forwardDeclared"), interner.intern("C"),
        ])
        func memberProperty(named name: String) -> SymbolID? {
            classChildren.first {
                sema.symbols.symbol($0)?.kind == .property
                    && sema.symbols.symbol($0)?.name == interner.intern(name)
            }
        }

        let s = try #require(memberProperty(named: "s"), "Missing property C.s")
        #expect(sema.symbols.delegateGetValueSymbol(for: s) == anyGetValue)

        let t = try #require(memberProperty(named: "t"), "Missing property C.t")
        #expect(sema.symbols.delegateGetValueSymbol(for: t) == anyGetValue)
        #expect(sema.symbols.delegateSetValueSymbol(for: t) == anySetValue)

        let sType = try #require(sema.symbols.propertyType(for: s))
        #expect(sema.types.isSubtype(sType, sema.types.stringType))
    }
}
#endif
