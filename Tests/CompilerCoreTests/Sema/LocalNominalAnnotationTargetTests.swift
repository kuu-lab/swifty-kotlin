import Foundation
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct LocalNominalAnnotationTargetTests {
    @Test(arguments: [false, true])
    func originalLocalClassAndParameterViolationsAreRejected(fromSource: Bool) throws {
        let context = try frontend(["""
        import kotlinx.serialization.*
        fun main() { @Required class Wrong(@param:Transient val value: Int) }
        """], fromSource: fromSource)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" })
        #expect(errors.contains { $0.message.contains("Required") })
        #expect(errors.contains { $0.message.contains("Transient") })
    }

    @Test(arguments: [false, true])
    func validHeaderMemberAndUseSiteTargetsPreservePropertyMetadata(fromSource: Bool) throws {
        let context = try frontend(["""
        import kotlinx.serialization.*
        @Target(AnnotationTarget.CLASS) annotation class ClassTag
        @Target(AnnotationTarget.CONSTRUCTOR) annotation class ConstructorTag
        @Target(AnnotationTarget.VALUE_PARAMETER) annotation class ParameterTag
        @Target(AnnotationTarget.FIELD) annotation class FieldTag
        @Target(AnnotationTarget.PROPERTY_GETTER) annotation class GetterTag
        @Target(AnnotationTarget.PROPERTY_SETTER) annotation class SetterTag
        @Target(AnnotationTarget.FUNCTION) annotation class FunctionTag
        @Target(AnnotationTarget.TYPE) annotation class TypeTag
        fun valid() {
            @ClassTag class Local @ConstructorTag constructor(
                @Required val requiredValue: Int,
                @Transient val temporaryValue: Int = 2,
                @param:ParameterTag @field:FieldTag @get:GetterTag @set:SetterTag var value: Int = 1
            ) {
                @ConstructorTag constructor(@ParameterTag text: String) : this(1)
                @FunctionTag fun member(@ParameterTag input: @TypeTag Int): Int = input
            }
            Local(1).member(2)
            val literal = object { @FunctionTag fun member(@ParameterTag value: Int): Int = value }
            literal.member(3)
        }
        """], fromSource: fromSource)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let ast = try #require(context.ast)
        let local = try #require(ast.arena.decls.compactMap { declaration -> ClassDecl? in
            guard case let .classDecl(value) = declaration,
                  context.interner.resolve(value.name) == "Local" else { return nil }
            return value
        }.first)
        #expect(local.annotations.map(\.name) == ["ClassTag"])
        #expect(local.primaryConstructorAnnotations.map(\.name) == ["ConstructorTag"])
        let secondary = try #require(local.secondaryConstructors.first)
        #expect(secondary.annotations.map(\.name) == ["ConstructorTag"])
        #expect(secondary.valueParams.first?.annotations.map(\.name) == ["ParameterTag"])
        let sema = try #require(context.sema)
        for (name, annotation) in [("requiredValue", "Required"), ("temporaryValue", "Transient")] {
            let property = try #require(sema.symbols.allSymbols().first {
                $0.kind == .property && context.interner.resolve($0.name) == name
            })
            let records = sema.symbols.annotations(for: property.id).filter {
                $0.annotationFQName == "kotlinx.serialization." + annotation
            }
            #expect(records.count == 1)
            #expect(records.first?.factorySymbol != nil)
        }
    }

    @Test(arguments: [false, true])
    func invalidLocalSitesAliasesAndLexicalShadowingAreRejected(fromSource: Bool) throws {
        let probes = [
            "fun bad() { @Required class Wrong }",
            "fun bad() { class Wrong @Required constructor() }",
            "fun bad() { class Wrong { @Required constructor(value: Int) {} } }",
            "fun bad() { class Wrong(@param:Required val value: Int) }",
            "fun bad() { class Wrong { constructor(@Transient value: Int) {} } }",
            "fun bad() { class Wrong { @Required fun member() {} } }",
            "fun bad() { class Wrong { fun member(@Transient value: Int) {} } }",
            "fun bad() { class Wrong(@field:Required val value: Int) }",
            "fun bad() { class Wrong(@get:Transient val value: Int) }",
            "fun bad() { class Wrong(@set:Required var value: Int) }",
            "fun bad() { class Wrong { val value: Int @Required get() = 1 } }",
            "fun bad() { val literal = object { @Required fun member() {} } }",
            "fun bad() { class Wrong { constructor(value: @Required Int) {} } }",
            "interface Base\nfun bad() { val literal = object : @Required Base {} }",
            "typealias Alias = Required\nfun bad() { class Wrong { fun member(value: @Alias Int) {} } }",
            "typealias Alias = Required\nfun bad() { @Alias class Wrong }",
            "fun bad() { @ImportedRequired class Wrong }",
            "class Outer { typealias Alias = Required; fun bad() { @Alias class Wrong } }",
            """
            @Target(AnnotationTarget.PROPERTY) annotation class Tag
            class Outer {
                @Target(AnnotationTarget.CLASS) annotation class Tag
                fun bad() { @Tag class Allowed(@param:Tag val value: Int) }
            }
            """,
            """
            @Target(AnnotationTarget.PROPERTY) annotation class Tag
            class Outer {
                @Target(AnnotationTarget.CLASS) annotation class Tag
                fun bad() {
                    class First { fun nested() { @Tag class Allowed(@param:Tag val value: Int) } }
                    First().nested()
                }
            }
            """,
        ]
        let sources = probes.enumerated().map { index, probe in
            let alias = probe.contains("ImportedRequired") ? "import kotlinx.serialization.Required as ImportedRequired" : ""
            return """
            package localprobe\(index)
            import kotlinx.serialization.*
            \(alias)
            \(probe)
            """
        }
        let context = try frontend(sources, fromSource: fromSource)
        for (index, probe) in probes.enumerated() {
            let file = try #require(context.sourceManager.fileID(forPath: inputPath(index)))
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error && $0.primaryRange?.start.file == file }
            #expect(errors.count == 1, "\(probe): \(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }, "\(probe): \(errors)")
        }
    }

    @Test(arguments: [false, true])
    func speculativeBuildersAndCompanionPrechecksDoNotLoseOrDuplicateTargets(fromSource: Bool) throws {
        let sources = ["""
        package builderprobe
        import kotlinx.serialization.*
        class Sink<T> { fun put(value: T) {} }
        fun <T> build(block: Sink<T>.() -> Unit): Sink<T> = Sink<T>().apply(block)
        fun bad() { val result = build { put(1); @Required class Wrong(@param:Transient val value: Int) } }
        """, """
        package companionprobe
        import kotlinx.serialization.*
        class Outer {
            companion object {
                fun bad() { @Required class Wrong }
            }
        }
        """]
        let context = try frontend(sources, fromSource: fromSource)
        for (index, count) in [(0, 2), (1, 1)] {
            let file = try #require(context.sourceManager.fileID(forPath: inputPath(index)))
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error && $0.primaryRange?.start.file == file }
            #expect(errors.count == count, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }, "\(errors)")
        }
    }

    private func inputPath(_ index: Int) -> String { "/tmp/local-nominal-annotation-target-\(index).kt" }

    private func frontend(_ sources: [String], fromSource: Bool) throws -> CompilationContext {
        let inputs = sources.indices.map(inputPath)
        let stdlib: String?
        if fromSource { stdlib = nil } else {
            TestStdlibCache.shared.prepare()
            stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        return CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "LocalNominalAnnotationTarget", inputs: inputs, outputPath: "/tmp/local-nominal-annotation-target",
            emit: .kirDump, target: defaultTargetTriple(), stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: Dictionary(uniqueKeysWithValues: zip(inputs, sources.map { Data($0.utf8) }))).context
    }
}
