#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func suppressWildcardsOnTypeArgumentKeepsControlVariance() throws {
        try withWorkspace { root in
            let source = """
            package fixture
            class Provider<T>
            class Consumer(val values: Map<Class<out CharSequence>, @JvmSuppressWildcards Provider<CharSequence>>)
            fun suppressed(values: List<@JvmSuppressWildcards CharSequence>): Int = values.size
            fun ordinary(values: List<CharSequence>): Int = values.size
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let owner = try jvmTool("javap", ["-classpath", app.path, "fixture.MainKt", "fixture.Consumer"], root: root)
            #expect(owner.stdout.contains("suppressed(java.util.List<java.lang.CharSequence>)"))
            #expect(owner.stdout.contains("ordinary(java.util.List<? extends java.lang.CharSequence>)"))
            #expect(owner.stdout.contains("fixture.Consumer(java.util.Map<java.lang.Class<? extends java.lang.CharSequence>, fixture.Provider<java.lang.CharSequence>>)"))
        }
    }
}
#endif
