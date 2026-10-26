@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct JvmRecordValidationTests {
    @Test(arguments: [false, true])
    func acceptsDataClassesAndResolvedAnnotations(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let sources = [
            """
            import kotlin.jvm.JvmRecord as Record
            interface Tag
            @Record data class Point(val x: Int, val y: Int) : Tag {
                val total: Int get() = x + y
                var computed: Int
                    get() = x
                    set(value) {}
                constructor() : this(0, 0)
                companion object { val count = 0 }
            }
            class Outer { @kotlin.jvm.JvmRecord data class Nested(val x: Int) }
            @JvmRecord data class PrivateConstructor private constructor(val x: Int)
            @JvmRecord value class FullValueRecord(val x: Int, val y: Int)
            """,
            """
            @Target(AnnotationTarget.CLASS)
            annotation class JvmRecord
            @JvmRecord class Other(val x: Int)
            """,
        ]
        for source in sources {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path], frontendFlags: ["full-value-classes"], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
                try runSema(ctx)
                #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            }
        }
    }

    @Test(arguments: [false, true])
    func rejectsInvalidRecordShapes(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        @JvmRecord class NotData(val x: Int)
        @JvmRecord data class Mutable(var x: Int)
        @JvmRecord data class AdditionalField(val x: Int) { val y: Int = x }
        @JvmRecord data class DelegatedField(val x: Int) { val y: Int by lazy { x } }
        @JvmRecord data class GetterField(val x: Int) {
            val y: Int = x
                get() = field
        }
        @JvmRecord data class SetterField(val x: Int) {
            var y: Int = x
                get() = x
                set(value) { field = value }
        }
        open class Base
        @JvmRecord data class Inherits(val x: Int) : Base()
        @JvmRecord data class ExplicitAny(val x: Int) : Any()
        interface Tag
        @JvmRecord data class Delegates(val x: Int, val tag: Tag) : Tag by tag
        @JvmRecord interface NotAClass
        fun local() { @JvmRecord data class Local(val x: Int) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-JVM-RECORD" }
            #expect(errors.count == 11, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let classNames = ["NotData", "Mutable", "AdditionalField", "DelegatedField", "GetterField",
                              "SetterField", "Inherits", "ExplicitAny", "Delegates", "Local"]
            for name in classNames {
                let declaration = try #require(ast.arena.decls.compactMap { decl -> ClassDecl? in
                    guard case let .classDecl(record) = decl, ctx.interner.resolve(record.name) == name else { return nil }
                    return record
                }.first)
                #expect(errors.filter { error in
                    error.primaryRange.map { declaration.range.contains($0) } ?? false
                }.count == 1, "Expected one @JvmRecord error for \(name): \(errors)")
            }
            let interface = try #require(ast.arena.decls.compactMap { decl -> InterfaceDecl? in
                guard case let .interfaceDecl(value) = decl, ctx.interner.resolve(value.name) == "NotAClass" else { return nil }
                return value
            }.first)
            #expect(errors.filter { error in
                error.primaryRange.map { interface.range.contains($0) } ?? false
            }.count == 1, "Expected one @JvmRecord error for NotAClass: \(errors)")
        }
    }

    @Test(arguments: [false, true])
    func deferredValidationPreservesOtherAnnotationChecks(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        import kotlin.jvm.JvmRecord as Record
        @Target(AnnotationTarget.FUNCTION) annotation class OnlyFunction
        @Target(AnnotationTarget.CLASS) annotation class Once

        @Record @OnlyFunction data class BadClassTarget(val x: Int)
        @Record data class BadMemberTarget(val x: Int) {
            @OnlyFunction val computed: Int get() = x
        }
        @Record data class Container(val x: Int) {
            @Record @OnlyFunction data class Nested(val y: Int)
        }
        @Record @Once @Once data class RepeatedOther(val x: Int)
        @Record @Record data class RepeatedRecord(val x: Int)
        @Record data class ShadowField(val x: Int) {
            val computed: Int get() { val field = x + 1; return field }
        }
        @Record class InvalidAlias(val x: Int)
        @kotlin.jvm.JvmRecord class InvalidQualified(val x: Int)
        fun local() { @Record data class Local(val x: Int) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
            let records = diagnostics.filter { $0.code == "KSWIFTK-SEMA-JVM-RECORD" }
            #expect(records.count == 3, "\(diagnostics)")
            #expect(records.filter { $0.message.contains("data or full value") }.count == 2, "\(records)")
            #expect(records.filter { $0.message.contains("local class") }.count == 1, "\(records)")
            #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }.count == 3, "\(diagnostics)")
            #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-NOT-REPEATABLE" }.count == 2, "\(diagnostics)")
        }
    }
}
