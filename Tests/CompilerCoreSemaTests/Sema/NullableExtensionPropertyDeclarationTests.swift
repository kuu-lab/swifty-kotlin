#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct NullableExtensionPropertyDeclarationTests {
    private func context(from sources: [String]) -> CompilationContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = sources.indices.map { index in
            directory.appendingPathComponent("input\(index).kt").path
        }
        let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        return ctx
    }

    @Test
    func nullableExtensionPropertyRegistersItsGetterAndSetter() throws {
        let ctx = context(from: ["""
        class A
        var A?.bar: Int
            get() = 42
            set(value) {}
        """])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Nullable extension property should type-check: \(errors)")
        let sema = try #require(ctx.sema)
        let property = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("bar")]).first { id in
            sema.symbols.symbol(id)?.kind == .property
                && sema.symbols.hasExtensionPropertyReceiver(id)
        })
        #expect(sema.symbols.extensionPropertyGetterAccessor(for: property) != nil)
        #expect(sema.symbols.extensionPropertySetterAccessor(for: property) != nil)
    }

    @Test
    func nullableExtensionPropertiesCoexistAcrossReceiversAndWithTopLevelProperty() throws {
        let ctx = context(from: ["""
        class A
        class B
        val marker: Int = 0
        val A?.marker: Int get() = 1
        val B?.marker: Int get() = 2
        """])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Distinct extension receivers and a top-level property may share a name: \(errors)")
    }

    @Test
    func duplicateNullableExtensionPropertyWithSameReceiverIsRejected() throws {
        let ctx = context(from: ["""
        class A
        val A?.marker: Int get() = 1
        val A?.marker: Int get() = 2
        """])
        try runSema(ctx)

        let duplicates = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0001" }
        #expect(duplicates.count == 1, "Expected one duplicate declaration diagnostic, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func matchingExpectAndActualNullableExtensionPropertiesStillLink() throws {
        let ctx = context(from: [
            """
            package sample
            expect class A
            expect val A?.marker: Int
            """,
            """
            package sample
            actual class A
            actual val A?.marker: Int get() = 1
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "A matching nullable extension property expect/actual pair should link: \(errors)")
    }

}
#endif
