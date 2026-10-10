#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ImplicitReceiverSmartCastPropertyTests {
    @Test(arguments: [
        "if (this is Names) return names; return original",
        "if (this !is Names) return original; return names",
        "return when (this) { is Names -> names; else -> original }",
    ])
    func extensionGetterResolvesNarrowedReceiver(body: String) throws {
        let ctx = makeContextFromSource("""
        interface Base { val original: String }
        interface Names { val names: String }
        val Base.read: String
            get() { \(body) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func objectInitializerUsesItsOwnReceiverBeforeOuterThis() throws {
        let ctx = makeContextFromSource("""
        class Outer(val value: Int) {
            fun read(): String {
                val obj = object {
                    val value = "inner"
                    val copied: String = value
                }
                return obj.copied
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "if (this is Names) return names; return original",
        "if (this !is Names) return original; return names",
        "if (this is Names) { return names + original }; return original",
        "if (this is Names && names == \"ok\") return names; return original",
    ])
    func narrowedThisResolvesBareProperties(body: String) throws {
        let ctx = makeContextFromSource("""
        interface Base { val original: String }
        interface Names { val names: String }
        fun Base.read(): String { \(body) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "if (this is Names) { val inside = names }; return names",
        "if (this !is Names) return names; return original",
        "if (this is Names) return 1.run { this.names }; return original",
    ])
    func narrowingDoesNotLeakOutsideItsReceiver(body: String) throws {
        let ctx = makeContextFromSource("""
        interface Base { val original: String }
        interface Names { val names: String }
        fun Base.read(): String { \(body) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error && $0.message.contains("names") }, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
