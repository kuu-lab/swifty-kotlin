#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedWorkManagerBuilderKeepsConcreteWorkerAndRequest() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package androidx.work
            open class ListenableWorker
            open class WorkRequest {
                abstract class Builder<B, W>(protected val worker: java.lang.Class<out ListenableWorker>) {
                    abstract fun setInitialDelay(delay: Long): B
                    abstract fun build(): W
                }
            }
            class OneTimeWorkRequest(val label: String) : WorkRequest() {
                class Builder(worker: java.lang.Class<out ListenableWorker>) :
                    WorkRequest.Builder<Builder, OneTimeWorkRequest>(worker) {
                    private var delay = 0L
                    override fun setInitialDelay(delay: Long): Builder {
                        this.delay = delay
                        return this
                    }
                    override fun build(): OneTimeWorkRequest = OneTimeWorkRequest(worker.simpleName + ":" + delay)
                }
            }
            inline fun <reified W : ListenableWorker> OneTimeWorkRequestBuilder(): OneTimeWorkRequest.Builder =
                OneTimeWorkRequest.Builder(W::class.java)
            """
            try provider.write(to: root.appendingPathComponent("OneTimeWorkRequest.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["OneTimeWorkRequest.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import androidx.work.ListenableWorker
            import androidx.work.OneTimeWorkRequest
            import androidx.work.OneTimeWorkRequestBuilder
            class RefreshWorker : ListenableWorker()
            fun request(): OneTimeWorkRequest = OneTimeWorkRequestBuilder<RefreshWorker>().setInitialDelay(12L).build()
            fun main() { println(request().label) }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "RefreshWorker:12\n")
        }
    }
}
#endif
