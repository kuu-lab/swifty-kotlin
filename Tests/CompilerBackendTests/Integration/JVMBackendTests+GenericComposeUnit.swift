#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedGenericComposableDiscardsUnitCarrier() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root, stdlib: stdlib)
            // Metadata from kotlinc with the Compose plugin for
            // @Composable fun <T> group(content: @Composable () -> T): T = content()
            let dependency = #"""
            package fixture;

            import androidx.compose.runtime.Composable;
            import androidx.compose.runtime.Composer;
            import kotlin.jvm.functions.Function2;

            @kotlin.Metadata(mv = {2, 4, 0}, k = 2, xi = 48,
                d1 = {"\000\026\012\002\010\003\012\002\030\002\012\002\030\002\012\000\012\002\030\002\012\002\010\002\0328\020\000\032\002H\001\"\004\010\000\020\0012\021\020\002\032\015\022\004\022\002H\0010\003¢\006\002\010\004H\007b\002\010\004b\014\010\006\022\010\010\007\022\004\010\010(\010¢\006\002\020\005"},
                d2 = {"group", "T", "content", "Lkotlin/Function0;", "Landroidx/compose/runtime/Composable;",
                      "(Lkotlin/jvm/functions/Function2;Landroidx/compose/runtime/Composer;I)Ljava/lang/Object;",
                      "Landroidx/compose/runtime/ComposableInferredTarget;", "scheme", "[0[0]]"})
            public final class ProducerKt {
                @Composable public static <T> T group(Function2<Composer, Integer, T> content, Composer composer, int changed) {
                    if (composer != Bridge.COMPOSER || changed != 0) throw new AssertionError("wrong composer");
                    return content.invoke(composer, changed);
                }
            }
            """#
            try dependency.write(to: root.appendingPathComponent("ProducerKt.java"), atomically: true, encoding: .utf8)
            let dependencyClasspath = [runtime.path, stdlib.path].joined(separator: ":")
            let producer = try jvmTool("javac", ["--release", "8", "-cp", dependencyClasspath,
                                                 "-d", "fixture", "ProducerKt.java"], root: root)
            try #require(producer.exitCode == 0, "\(producer.stderr)")

            let consumer = """
            import androidx.compose.runtime.Composable
            import fixture.group

            @Composable fun Screen() {
                group { println("session") }
            }
            """
            let classpath = [root.appendingPathComponent("fixture").path, runtime.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", consumer)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let driver = """
            import fixture.Bridge;
            public final class Driver {
                public static void main(String[] args) {
                    ScreenKt.Screen(Bridge.COMPOSER, 0);
                    Bridge.checkClosed(2);
                }
            }
            """
            try driver.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let runClasspath = ([app.path] + classpath).joined(separator: ":")
            let compiled = try jvmTool("javac", ["-cp", runClasspath, "-d", "driver", "Driver.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", runClasspath + ":" + root.appendingPathComponent("driver").path, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "session\n")
        }
    }
}
#endif
