#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct InapplicableMemberExtensionResolutionTests {
    @Test
    func qualifiedCallFallsBackToApplicableExtension() throws {
        let source = """
        class Box {
            fun append(a: Int, b: Int, c: Int): String = "member"
            fun score(value: Int): Int = value + 1
        }
        fun Box.append(value: Int): String = "extension"
        fun Box.score(value: String): Int = score(7)
        fun use(): Int {
            val box = Box()
            box.append(1)
            box.append(1, 2, 3)
            return box.score("x") + box.score(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected member and extension overloads to coexist: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func superCallNeverResolvesToExtension() throws {
        let source = """
        open class Base {
            fun h(x: String): Int = 1
        }
        fun Base.h(x: Int): Int = 2
        class D : Base() {
            fun test(): Int = super.h(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "super calls must not bind extensions: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func invisibleMemberDoesNotShadowExtension() throws {
        let source = """
        class C {
            private fun g(): Int = 0
        }
        fun C.g(x: Int): Int = x
        fun use(): Int = C().g(2)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "An inaccessible member must not shadow a resolvable extension: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
