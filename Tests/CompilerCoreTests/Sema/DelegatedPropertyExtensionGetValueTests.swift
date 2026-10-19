#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing

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
}
#endif
