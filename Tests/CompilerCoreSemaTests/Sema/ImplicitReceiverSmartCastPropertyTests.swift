#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    @Test
    func narrowedMemberThisResolvesBareTopLevelExtensionProperty() throws {
        let ctx = makeContextFromSource("""
        open class Base {
            fun read(): String {
                if (this is Child) return marker
                return "FAIL"
            }
        }
        class Child : Base()
        val Child.marker: String get() = "OK"
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func bareTopLevelExtensionPropertyRejectsUnnarrowedMemberThis() throws {
        let ctx = makeContextFromSource("""
        open class Base {
            fun read(): String = marker
        }
        class Child : Base()
        val Child.marker: String get() = "OK"
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.message.contains("marker")
        }, "Expected the un-narrowed Base receiver to reject marker: \(ctx.diagnostics.diagnostics)")
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

    // KUU-4473: a stable `val` member of the enclosing class smart-casts
    // inside an inline receiver lambda such as `buildString {}`.
    @Test(arguments: [
        // The reported pattern: StringBuilder receiver lambda.
        """
        internal class C(val alias: String?) {
            private val t = buildString {
                if (alias != null) {
                    append(" as ${'$'}{alias.trim()}")
                }
            }
            fun show() = t
        }
        """,
        // Doubly-nested receiver lambdas keep the outer class receiver.
        """
        internal class C(val alias: String?) {
            private val t = buildString {
                with(1) {
                    if (alias != null) {
                        append(alias.trim())
                    }
                }
            }
            fun show() = t
        }
        """,
        // The member-function receiver works the same way as an initializer.
        """
        internal class C(val alias: String?) {
            fun show() = buildString {
                if (alias != null) {
                    append(alias.trim())
                } else {
                    append("none")
                }
            }
        }
        """,
    ])
    func outerClassValMemberSmartCastsInsideReceiverLambda(body: String) throws {
        let ctx = makeContextFromSource(body)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // Unstable properties must not narrow even through the outer receiver.
    @Test(arguments: [
        // `var` can be mutated concurrently — no smart cast.
        """
        internal class C(var alias: String?) {
            private val t = buildString {
                if (alias != null) {
                    append(alias.trim())
                }
            }
            fun show() = t
        }
        """,
        // A custom getter can return a different value per call.
        """
        internal class C(private val raw: String?) {
            val alias: String? get() = raw
            private val t = buildString {
                if (alias != null) {
                    append(alias.trim())
                }
            }
            fun show() = t
        }
        """,
    ])
    func unstableOuterMemberDoesNotSmartCastInsideReceiverLambda(body: String) throws {
        let ctx = makeContextFromSource(body)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
