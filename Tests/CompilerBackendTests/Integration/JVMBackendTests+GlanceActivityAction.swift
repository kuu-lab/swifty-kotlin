#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedGlanceReifiedActivityActionUsesClassOverload() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let activity = """
            package android.app
            open class Activity
            """
            let provider = """
            package androidx.glance.action
            import android.app.Activity
            class ActionParameters(val value: String)
            class Action(val target: String)
            fun <T : Activity> actionStartActivity(
                activity: java.lang.Class<T>, parameters: ActionParameters = ActionParameters("default")
            ): Action = Action(activity.simpleName + ":" + parameters.value)
            inline fun <reified T : Activity> actionStartActivity(
                parameters: ActionParameters = ActionParameters("default")
            ): Action = actionStartActivity(T::class.java, parameters)
            """
            try activity.write(to: root.appendingPathComponent("Activity.kt"), atomically: true, encoding: .utf8)
            try provider.write(to: root.appendingPathComponent("StartActivityAction.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Activity.kt", "StartActivityAction.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import android.app.Activity
            import androidx.glance.action.ActionParameters
            import androidx.glance.action.actionStartActivity
            class MainActivity : Activity()
            fun main() {
                println(actionStartActivity<MainActivity>().target)
                println(actionStartActivity<MainActivity>(parameters = ActionParameters("explicit")).target)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "MainActivity:default\nMainActivity:explicit\n")
        }
    }
}
#endif
