#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func composeViewContentIsDeclaredOnceWhenKotlinMetadataIsPresent() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root, stdlib: own)
            let source = """
            package androidx.compose.ui.platform
            import androidx.compose.runtime.Composable
            import androidx.compose.runtime.Composer
            import fixture.Bridge

            class ComposeView {
                fun setContent(content: @Composable (Composer, Int) -> Unit) {
                    content(Bridge.COMPOSER, 0)
                }
            }
            """
            try source.write(to: root.appendingPathComponent("ComposeView.kt"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("view.jar").path
            let producer = try jvmTool(
                "kotlinc", ["ComposeView.kt", "-classpath", runtime.path, "-d", classes], root: root
            )
            try #require(producer.exitCode == 0, "\(producer.stderr)")
            let classpath = [classes, runtime.path, own.path]
            let consumer = """
            import androidx.compose.ui.platform.ComposeView

            fun main() { ComposeView().setContent { println("content") } }
            """
            let (_, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", consumer)], name: "app.jar", classpath: classpath
            )
            #expect(exit == 0, "\(diagnostics.map(\.message))")
        }
    }
}
#endif
