#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmComposableCallsThreadComposerAndCloseGroups() throws {
        try withWorkspace { root in
            let dependencies = try composeJVMFixture(root)
            let source = """
                import androidx.compose.runtime.Composable
                import androidx.compose.runtime.ReadOnlyComposable
                import androidx.compose.runtime.currentComposer as composer
                import fixture.Bridge

                @Composable private fun Leaf(value: Int) { Bridge.record(composer, value) }

                @Composable fun Root(which: Int) {
                    if (which == 0) return
                    if (which == 1) Leaf(1) else Leaf(2)
                }

                @Composable @ReadOnlyComposable fun ReadOnly(): Int = Bridge.depth(composer)
                """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Screen.kt", source)], name: "app.jar", classpath: [dependencies.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let classpath = app.path + ":" + dependencies.path
            let bytecode = try javap(["-v", "-p", "-classpath", classpath, "ScreenKt"])
            #expect(bytecode.stdout.contains("(ILandroidx/compose/runtime/Composer;I)V"))
            #expect(bytecode.stdout.contains("RuntimeInvisibleAnnotations:"))
            #expect(bytecode.stdout.contains("androidx.compose.runtime.Composable"))

            let driver = """
                import fixture.Bridge;
                public final class Driver {
                    public static void main(String[] args) {
                        ScreenKt.Root(0, Bridge.COMPOSER, 0);
                        Bridge.checkClosed(1);
                        ScreenKt.Root(1, Bridge.COMPOSER, 0);
                        Bridge.checkClosed(3);
                        int firstSite = Bridge.keys[1];
                        ScreenKt.Root(2, Bridge.COMPOSER, 0);
                        Bridge.checkClosed(3);
                        if (firstSite == Bridge.keys[1]) throw new AssertionError("call sites share a key");
                        if (ScreenKt.ReadOnly(Bridge.COMPOSER, 0) != 0) throw new AssertionError("read-only call opened a group");
                        Bridge.checkClosed(0);
                    }
                }
                """
            try driver.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", classpath, "-d", "driver", "Driver.java"], root: root)
            let run = try java(["-Xverify:all", "-cp", classpath + ":" + root.appendingPathComponent("driver").path, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "1\n2\n")
        }
    }

    @Test
    func jvmComposableRejectsUnsupportedDefaults() throws {
        try withWorkspace { root in
            let dependencies = try composeJVMFixture(root)
            let source = """
                import androidx.compose.runtime.Composable
                @Composable fun Screen(value: Int = 1) {}
                """
            let result = try m22Build(root: root, sources: [("Screen.kt", source)], name: "app.jar", classpath: [dependencies.path])
            #expect(result.1 == 1)
            #expect(result.2.contains { $0.message.contains("without default arguments") })
        }
    }

    @Test
    func jvmComposeViewWrapsKotlinContent() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependencies = try composeJVMFixture(root, stdlib: stdlib)
            let source = """
                import androidx.compose.foundation.text.BasicText
                import androidx.compose.runtime.Composable
                import androidx.compose.ui.platform.ComposeView

                @Composable private fun Screen(text: String) { BasicText(text) }

                fun main() {
                    val text = "Kotlin Compose"
                    ComposeView().setContent { Screen(text) }
                }
                """
            let classpath = [dependencies.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "Kotlin Compose\n")
        }
    }

    private func composeJVMFixture(_ root: URL, stdlib: URL? = nil) throws -> URL {
        var sources = [
            "Composable.java": """
                package androidx.compose.runtime;
                import java.lang.annotation.*;
                @Retention(RetentionPolicy.CLASS) @Target(ElementType.METHOD)
                public @interface Composable {}
                """,
            "Composer.java": """
                package androidx.compose.runtime;
                public interface Composer {
                    void startReplaceableGroup(int key);
                    void endReplaceableGroup();
                }
                """,
            "ReadOnlyComposable.java": """
                package androidx.compose.runtime;
                import java.lang.annotation.*;
                @Retention(RetentionPolicy.CLASS) @Target(ElementType.METHOD)
                public @interface ReadOnlyComposable {}
                """,
            "ComposablesKt.java": """
                package androidx.compose.runtime;
                public class ComposablesKt {
                    public static Composer getCurrentComposer(Composer composer, int changed) {
                        throw new AssertionError("currentComposer must be lowered");
                    }
                }
                """,
            "Bridge.java": """
                package fixture;
                import androidx.compose.runtime.Composer;
                public class Bridge {
                    private static int depth;
                    private static int groups;
                    public static int[] keys = new int[3];
                    public static final Composer COMPOSER = new Composer() {
                        public void startReplaceableGroup(int key) { keys[depth++] = key; groups++; }
                        public void endReplaceableGroup() { depth--; }
                    };
                    public static void checkClosed(int expected) {
                        if (depth != 0 || groups != expected) throw new AssertionError("unbalanced groups");
                        groups = 0;
                    }
                    public static void record(Composer composer, int value) {
                        if (composer != COMPOSER || depth != 3) throw new AssertionError("wrong composer");
                        System.out.println(value);
                    }
                    public static int depth(Composer composer) {
                        if (composer != COMPOSER) throw new AssertionError("wrong composer");
                        return depth;
                    }
                }
                """,
        ]
        if stdlib != nil {
            sources.merge(composeUIFixtureSources) { _, new in new }
        }
        for (name, source) in sources {
            try source.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let classpath = stdlib.map { ["-cp", $0.path] } ?? []
        _ = try jvmTool("javac", ["--release", "8", "-d", "dependencies"] + classpath + sources.keys.sorted(), root: root)
        if stdlib != nil {
            // Java source cannot spell a Kotlin value-class-mangled JVM method name.
            let path = root.appendingPathComponent("dependencies/androidx/compose/foundation/text/BasicTextKt.class")
            var bytes = try Data(contentsOf: path)
            let name = try #require(bytes.range(of: Data("BasicText_VhcvRP8".utf8)))
            bytes.replaceSubrange(name, with: Data("BasicText-VhcvRP8".utf8))
            try bytes.write(to: path)
        }
        _ = try jvmTool("jar", ["cf", "dependencies.jar", "-C", "dependencies", "."], root: root)
        return root.appendingPathComponent("dependencies.jar")
    }

    private var composeUIFixtureSources: [String: String] {
        [
            "ComposableLambda.java": """
                package androidx.compose.runtime.internal;
                import androidx.compose.runtime.Composer;
                import kotlin.Unit;
                import kotlin.jvm.functions.Function2;
                public interface ComposableLambda extends Function2<Composer, Integer, Unit> {}
                """,
            "ComposableLambdaKt.java": """
                package androidx.compose.runtime.internal;
                import androidx.compose.runtime.Composer;
                import kotlin.Unit;
                import kotlin.jvm.functions.Function2;
                public class ComposableLambdaKt {
                    @SuppressWarnings("unchecked")
                    public static ComposableLambda composableLambdaInstance(int key, boolean tracked, Object body) {
                        if (!tracked) throw new AssertionError("untracked content");
                        Function2<Composer, Integer, Unit> content = (Function2<Composer, Integer, Unit>) body;
                        return content::invoke;
                    }
                }
                """,
            "ComposeView.java": """
                package androidx.compose.ui.platform;
                import androidx.compose.runtime.Composer;
                import androidx.compose.runtime.internal.ComposableLambda;
                import fixture.Bridge;
                import kotlin.Unit;
                import kotlin.jvm.functions.Function2;
                public class ComposeView {
                    public void setContent(Function2<? super Composer, ? super Integer, Unit> content) {
                        if (!(content instanceof ComposableLambda)) throw new AssertionError("missing Compose wrapper");
                        if (content.invoke(Bridge.COMPOSER, 0) != Unit.INSTANCE) throw new AssertionError("missing Unit");
                        Bridge.checkClosed(2);
                    }
                    public void setViewCompositionStrategy(ViewCompositionStrategy strategy) {}
                }
                """,
            "ViewCompositionStrategy.java": """
                package androidx.compose.ui.platform;
                import kotlin.Unit;
                import kotlin.jvm.functions.Function0;
                public interface ViewCompositionStrategy {
                    Function0<Unit> installFor(ComposeView view);
                }
                """,
            "BasicTextKt.java": """
                package androidx.compose.foundation.text;
                import androidx.compose.runtime.Composer;
                import androidx.compose.ui.Modifier;
                import androidx.compose.ui.graphics.ColorProducer;
                import androidx.compose.ui.text.TextStyle;
                import fixture.Bridge;
                import kotlin.jvm.functions.Function1;
                public class BasicTextKt {
                    public static void BasicText_VhcvRP8(String text, Modifier modifier, TextStyle style, Function1 callback,
                            int overflow, boolean softWrap, int maxLines, int minLines, ColorProducer color,
                            Composer composer, int changed, int defaults) {
                        if (Bridge.depth(composer) != 2 || changed != 0 || defaults != 0x1FE)
                            throw new AssertionError("incorrect Compose call");
                        if (modifier != null || style != null || callback != null || overflow != 0 || softWrap
                                || maxLines != 0 || minLines != 0 || color != null)
                            throw new AssertionError("incorrect default placeholders");
                        System.out.println(text);
                    }
                }
                """,
            "Modifier.java": "package androidx.compose.ui; public interface Modifier {}",
            "TextStyle.java": "package androidx.compose.ui.text; public class TextStyle {}",
            "ColorProducer.java": "package androidx.compose.ui.graphics; public interface ColorProducer {}",
        ]
    }
}
#endif
