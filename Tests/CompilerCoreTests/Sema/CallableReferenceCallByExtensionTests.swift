#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableReferenceCallByExtensionTests {
    private func check(_ sources: [String], mode: EmitMode, expectsError: Bool = false) throws {
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: mode)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError == expectsError, "\(ctx.diagnostics.diagnostics)")
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }

    @Test(arguments: [EmitMode.kirDump])
    func stringExtensionsKeepTheirExpectedArgumentAndReturnTypes(mode: EmitMode) throws {
        try check(["""
        import kotlin.reflect.*
        fun (() -> Int).callBy(label: String): String = "custom:" + label
        fun (() -> Int).withLabel(label: String): String = "control:" + label
        fun <T : String> label(): T = "generic" as T
        fun value(): Int = 42
        fun check() {
            val ref = ::value
            val control: String = ref.withLabel("x")
            val custom: String = ref.callBy("x")
            val generic: String = ref.callBy(label())
            val member: Int = ref.callBy(emptyMap())
            val explicit: Int = ref.callBy(emptyMap<KParameter, Any?>())
            val erased: Any? = (ref as KFunction<*>).callBy(emptyMap())
        }
        """], mode: mode)
    }

    @Test(arguments: [EmitMode.kirDump])
    func mapExtensionDoesNotDisplaceApplicableReflectiveMember(mode: EmitMode) throws {
        try check(["""
        import kotlin.reflect.*
        fun (() -> Int).callBy(args: Map<String, Any?>): String = "custom"
        fun value(): Int = 42
        fun check() {
            val ref = ::value
            val custom: String = ref.callBy(emptyMap<String, Any?>())
            val populated: String = ref.callBy(mapOf("label" to 1))
            val member: Int = ref.callBy(emptyMap())
            val explicit: Int = ref.callBy(emptyMap<KParameter, Any?>())
        }
        """], mode: mode)
    }

    @Test(arguments: [EmitMode.kirDump])
    func explicitlyImportedExtensionIsVisible(mode: EmitMode) throws {
        try check(["""
        package extras
        fun (() -> Int).callBy(label: String): String = label
        """, """
        package consumer
        import extras.callBy
        fun value(): Int = 42
        fun check(): String = (::value).callBy("imported")
        """], mode: mode)
    }

    @Test(arguments: [EmitMode.kirDump])
    func unimportedExtensionDoesNotBecomeVisible(mode: EmitMode) throws {
        try check(["""
        package extras
        fun (() -> Int).callBy(label: String): String = label
        """, """
        package consumer
        fun value(): Int = 42
        fun check(): String = (::value).callBy("unimported")
        """], mode: mode, expectsError: true)
    }

    @Test(arguments: [EmitMode.kirDump])
    func inapplicableExtensionDoesNotAllowAnInvalidMemberMap(mode: EmitMode) throws {
        try check(["""
        import kotlin.reflect.*
        fun (() -> Int).callBy(label: Boolean): String = "custom"
        fun value(): Int = 42
        fun check() { (::value).callBy(emptyMap<String, Any?>()) }
        """], mode: mode, expectsError: true)
    }
}
#endif
