#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// With Compose Foundation's real classfiles on the classpath, the
    /// Kotlin-metadata member `LazyListScope.items(count, key, contentType,
    /// itemContent)` reached Sema as a stub whose `@Composable` lambda had
    /// lost its annotation. Members win over extensions, so it shadowed the
    /// hand-written `items(count) { ... }` contract and
    /// `LazyColumn { items(n) { index -> BasicText(...) } }` failed with
    /// KSWIFTK-SEMA-0493.
    @Test
    func lazyListItemsContractWinsOverItsKotlinMetadataMember() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root, stdlib: own)
            // The shape Compose Foundation 1.7 publishes: a member with
            // defaults whose lowered content slot is Function4 (receiver,
            // index, Composer, changed), plus the static `items$default`.
            try """
            package androidx.compose.foundation.lazy
            import androidx.compose.runtime.Composable
            import androidx.compose.runtime.Composer

            interface LazyItemScope

            interface LazyListScope {
                fun items(
                    count: Int,
                    key: ((Int) -> Any)? = null,
                    contentType: (Int) -> Any? = { null },
                    itemContent: @Composable Function4<LazyItemScope, Int, Composer, Int, Unit>
                ) {}
            }
            """.write(to: root.appendingPathComponent("Lazy.kt"), atomically: true, encoding: .utf8)
            let lazy = root.appendingPathComponent("lazy.jar")
            let compiled = try jvmTool(
                "kotlinc", ["Lazy.kt", "-Xjvm-default=all", "-classpath", runtime.path, "-d", lazy.path], root: root
            )
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = """
            import androidx.compose.foundation.lazy.LazyListScope
            import androidx.compose.foundation.lazy.items
            import androidx.compose.runtime.Composable

            @Composable fun Row(index: Int) { println(index) }

            fun LazyListScope.rows(count: Int) {
                items(count) { index -> Row(index) }
            }
            """
            let (_, exit, diagnostics) = try m22Build(
                root: root, sources: [("Rows.kt", consumer)], name: "app.jar", classpath: [lazy.path, runtime.path, own.path]
            )
            #expect(exit == 0, "\(diagnostics.map(\.message))")
            #expect(!diagnostics.contains { $0.code == "KSWIFTK-SEMA-0493" })
        }
    }
}
#endif
