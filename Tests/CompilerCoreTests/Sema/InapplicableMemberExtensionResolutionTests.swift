#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct InapplicableMemberExtensionResolutionTests {
    @Test
    func bundledNonGenericExtensionsRemainVisibleBesideMembers() throws {
        let declaration = """
        package sample.library
        class Reader {
            fun readTo(value: Int, count: Long): Int = value
            fun indexOf(value: Int, start: Long = 0L): Long = start
        }
        fun Reader.readTo(value: String, start: Int = 0, end: Int = 1): Int = start
        fun Reader.indexOf(value: String, start: Long = 0L): Long = start
        """
        let usage = """
        import sample.library.*
        fun use(reader: Reader): Long {
            reader.readTo("bytes")
            reader.readTo("bytes", 1, 2)
            reader.readTo(1, 2L)
            reader.indexOf(1)
            return reader.indexOf("pattern", 2L)
        }
        """
        try withTemporaryFile(contents: usage) { path in
            let ctx = makeCompilationContext(inputs: [path])
            _ = ctx.sourceManager.addFile(
                path: "__bundled_reader.kt",
                contents: Data(declaration.utf8),
                origin: .bundledStdlib
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected bundled extension fallback: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func mixedNumericAndNominalOverloadsContextualizeLiterals() throws {
        let source = """
        class Reader
        fun Reader.find(value: Byte, start: Long = 0L): Long = start
        fun Reader.find(value: String, start: Long = 0L): Long = start
        fun use(reader: Reader): Long = reader.find(1) + reader.find(-1, 2L)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected integer literal contextualization: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func mixedOverloadsMapReorderedNamedArgumentsBeforeContextualizingLiterals() throws {
        let source = """
        fun choose(a: Byte, b: String): String = "byte"
        fun choose(a: String, b: Int): String = "int"
        fun use(): String = choose(b = 1, a = "x")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected named arguments to drive literal types: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func mixedOverloadsRejectOutOfRangeConstantsAndIntVariables() throws {
        let source = """
        class Reader
        fun Reader.find(value: Byte): Int = 1
        fun Reader.find(value: String): Int = 2
        fun use(reader: Reader, value: Int) {
            reader.find(128)
            reader.find(value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.count == 2)
        }
    }

    @Test
    func bundledExtensionsStillRequireImport() throws {
        let declaration = """
        package sample.library
        class Reader { fun readTo(value: Int): Int = value }
        fun Reader.readTo(value: String): Int = 0
        """
        let usage = """
        import sample.library.Reader
        fun use(reader: Reader): Int = reader.readTo("bytes")
        """
        try withTemporaryFile(contents: usage) { path in
            let ctx = makeCompilationContext(inputs: [path])
            _ = ctx.sourceManager.addFile(
                path: "__bundled_reader.kt",
                contents: Data(declaration.utf8),
                origin: .bundledStdlib
            )
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
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
