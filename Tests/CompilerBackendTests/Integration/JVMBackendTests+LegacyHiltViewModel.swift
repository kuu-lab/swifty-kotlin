#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func legacyHiltViewModelUsesReifiedModelAndSuppliedOrLocalOwner() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root)
            let providers = [
                ("Lifecycle.kt", """
                package androidx.lifecycle
                interface ViewModelStoreOwner
                open class ViewModel(val label: String)
                class ViewModelProvider {
                    interface Factory {
                        fun create(model: Class<*>): ViewModel
                    }
                }
                """),
                ("CreationExtras.kt", """
                package androidx.lifecycle.viewmodel
                class CreationExtras
                """),
                ("ViewModel.kt", """
                package androidx.lifecycle.viewmodel.compose
                import androidx.compose.runtime.Composer
                import androidx.lifecycle.ViewModel
                import androidx.lifecycle.ViewModelProvider
                import androidx.lifecycle.ViewModelStoreOwner
                import androidx.lifecycle.viewmodel.CreationExtras
                data class Owner(val label: String) : ViewModelStoreOwner
                object LocalViewModelStoreOwner {
                    fun getCurrent(composer: Composer, changed: Int): ViewModelStoreOwner = Owner("local")
                }
                fun viewModel(model: Class<*>, owner: ViewModelStoreOwner, key: String?, factory: ViewModelProvider.Factory,
                    extras: CreationExtras?, composer: Composer, changed: Int, defaults: Int): ViewModel {
                    check(key == null && extras == null && changed == 0 && defaults == 16)
                    return factory.create(model)
                }
                """),
                ("HiltViewModel.kt", """
                package androidx.hilt.navigation.compose
                import androidx.compose.runtime.Composer
                import androidx.lifecycle.ViewModel
                import androidx.lifecycle.ViewModelProvider
                import androidx.lifecycle.ViewModelStoreOwner
                import androidx.lifecycle.viewmodel.compose.Owner
                inline fun <reified VM : ViewModel> hiltViewModel(owner: ViewModelStoreOwner?, composer: Composer, changed: Int, defaults: Int): VM =
                    error("The reified method must be lowered at the call site")
                fun createHiltViewModelFactory(owner: ViewModelStoreOwner, composer: Composer, changed: Int): ViewModelProvider.Factory =
                    object : ViewModelProvider.Factory {
                        override fun create(model: Class<*>): ViewModel = model.getConstructor(String::class.java).newInstance((owner as Owner).label) as ViewModel
                    }
                """),
            ]
            for (file, content) in providers {
                try content.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            }
            let dependency = root.appendingPathComponent("dependency.jar").path
            let compiled = try jvmTool(
                "kotlinc", providers.map { $0.0 } + ["-classpath", runtime.path, "-d", dependency], root: root
            )
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [runtime.path, dependency, own.path]
            let source = """
            import androidx.compose.runtime.Composable
            import androidx.hilt.navigation.compose.hiltViewModel
            import androidx.lifecycle.ViewModel
            import androidx.lifecycle.viewmodel.compose.Owner
            class Model(label: String) : ViewModel(label)
            @Composable fun withDefault(): String = hiltViewModel<Model>().label
            @Composable fun withExplicit(): String = hiltViewModel<Model>(Owner("explicit")).label
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let driver = """
            import androidx.compose.runtime.Composer;
            public class Driver {
                public static void main(String[] args) {
                    Composer composer = new Composer() {
                        public void startReplaceableGroup(int key) {}
                        public void endReplaceableGroup() {}
                    };
                    System.out.println(ScreenKt.withDefault(composer, 0));
                    System.out.println(ScreenKt.withExplicit(composer, 0));
                }
            }
            """
            try driver.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let appClasspath = ([app.path] + classpath).joined(separator: ":")
            let javaBuild = try jvmTool("javac", ["-cp", appClasspath, "-d", "driver", "Driver.java"], root: root)
            try #require(javaBuild.exitCode == 0, "\(javaBuild.stderr)")
            let driverPath = root.appendingPathComponent("driver").path
            let result = try java(["-Xverify:all", "-cp", appClasspath + ":" + driverPath, "Driver"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "local\nexplicit\n")
        }
    }
}
#endif
