#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct InapplicableMemberExtensionResolutionTests {
    @Test
    func bundledNonGenericExtensionCoexistsWithMemberOverloads() throws {
        let source = """
        import kotlinx.io.Buffer
        import kotlinx.io.Sink
        import kotlinx.io.bytestring.ByteString
        import kotlinx.io.write

        fun use(buffer: Buffer, sink: Sink, bytes: ByteString) {
            buffer.write(bytes)
            sink.write(bytes, 1, 2)
            buffer.write(byteArrayOf(1, 2))
            sink.write(byteArrayOf(1, 2), 1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected bundled extensions and members to coexist: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func bundledExtensionRequiresAnImportWhenMembersExist() throws {
        let source = """
        import kotlinx.io.Buffer
        import kotlinx.io.bytestring.ByteString

        fun use(buffer: Buffer, bytes: ByteString) {
            buffer.write(bytes)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
        }
    }

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
