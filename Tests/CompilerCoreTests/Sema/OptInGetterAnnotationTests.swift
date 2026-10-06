#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

@Suite
struct OptInGetterAnnotationTests {
    @Test(arguments: ["WARNING", "ERROR"], [false, true])
    func rejectsOptInMarkerOnGetter(level: String, blockBody: Bool) throws {
        let body = blockBody ? "{ return length }" : "= length"
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.\(level))
        @Target(AnnotationTarget.PROPERTY_GETTER)
        annotation class ExperimentalGetter
        val String.experimentalLength: Int
            @ExperimentalGetter
            get() \(body)
        fun main() { println("x".experimentalLength) }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN-GETTER", in: ctx)
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(errors.allSatisfy(isError))
        #expect(errors.first?.message == "Opt-in requirement marker annotation cannot be used on getter.")
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" })
    }

    @Test(arguments: [
        "@get:ExperimentalGetter val length: Int = 1",
        "class Host(@get:ExperimentalGetter val length: Int)",
        "val length: Int\n    @ExperimentalGetter\n    get() = 1",
        "val length: Int @ExperimentalGetter get() = 1",
        "val length: Int @ExperimentalGetter get() { return 1 }",
    ])
    func rejectsOptInGetterMarkerWithoutExplicitTarget(property: String) throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn(level = RequiresOptIn.Level.WARNING)
        annotation class ExperimentalGetter
        \(property)
        """)
        let errors = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN-GETTER", in: ctx)
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(errors.allSatisfy(isError))
    }

    @Test
    func acceptsOrdinaryGetterAnnotationAndKeepsFollowingDeclaration() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @Target(AnnotationTarget.PROPERTY_GETTER)
        annotation class GetterAnnotation
        val length: Int
            @GetterAnnotation
            get() = 1
        @GetterAnnotation
        fun invalidTarget() = 1
        """)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN-GETTER", in: ctx).isEmpty)
        let targetErrors = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(targetErrors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(targetErrors.first?.message.contains("function") == true)
        let ast = try #require(ctx.ast)
        let property = try #require(ast.files.first?.topLevelDecls.compactMap { id -> PropertyDecl? in
            guard case let .propertyDecl(property) = ast.arena.decl(id) else { return nil }
            return property
        }.first)
        #expect(property.annotations.isEmpty)
        #expect(property.getter?.annotations.map(\.name) == ["GetterAnnotation"])
    }

    @Test
    func getterOptInDoesNotLeakToSiblingProperty() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        annotation class ExperimentalApi
        @ExperimentalApi
        fun unstable() = 1
        val accepted: Int
            @OptIn(ExperimentalApi::class)
            get() = unstable()
        val rejected: Int
            get() = unstable()
        """)
        let errors = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(errors.allSatisfy(isError))
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN-GETTER", in: ctx).isEmpty)
    }

    @Test
    func acceptsPropertyMarkerAndGetterOptIn() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn(level = RequiresOptIn.Level.WARNING)
        @Target(AnnotationTarget.PROPERTY)
        annotation class ExperimentalProperty
        @ExperimentalProperty
        val length: Int
            @OptIn(ExperimentalProperty::class)
            get() = experimentalValue
        @ExperimentalProperty
        val experimentalValue: Int = 1
        fun use() = length
        """)
        #expect(!ctx.diagnostics.diagnostics.contains(where: isError), "\(ctx.diagnostics.diagnostics)")
        let warnings = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)
        #expect(warnings.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(warnings.allSatisfy(isWarning))
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: true)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Each test asserts the expected diagnostics.
        }
        return ctx
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func isError(_ diagnostic: Diagnostic) -> Bool {
        diagnostic.severity == .error
    }

    private func isWarning(_ diagnostic: Diagnostic) -> Bool {
        diagnostic.severity == .warning
    }

}
#endif
