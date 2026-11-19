#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func oversizedClasspathFallsBackToReferencedLazyInjection() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)

            let eager = try JVMClasspathIndex.load([dependency.path])
            #expect(eager.lazyClassNames.isEmpty)
            #expect(eager.classes["dep/Counter"] != nil)

            let lazy = try JVMClasspathIndex.load(
                [dependency.path], automaticLazyClasspathMemberLimit: 1
            )
            #expect(lazy.classes["dep/Counter"] != nil)
            #expect(lazy.lazyClassNames.contains("dep/Counter"))
            #expect(lazy.lazyClassNames.contains("dep/Child"))
        }
    }

    @Test
    func lazyFileFacadeMembersAreReachableFromImports() throws {
        try withWorkspace { root in
            try """
            package fixture

            class Widget

            suspend fun Widget.render(content: (Int, Int) -> Unit) {
                content(20, 22)
            }
            """.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Provider.kt", "-d", "provider.jar"], root: root)
            let provider = root.appendingPathComponent("provider.jar")
            let index = try JVMClasspathIndex.load(
                [provider.path], automaticLazyClasspathMemberLimit: 1
            )
            #expect(index.lazyClassNames.contains("fixture/ProviderKt"))
            #expect(index.lazyClassNames.contains("fixture/Widget"))

            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "LazyFacadeTest",
                    inputs: [consumerPath],
                    outputPath: root.appendingPathComponent("out").path,
                    emit: .jvmJar,
                    target: .hostDefault(),
                    includeStdlib: false,
                    allowDefaultStdlibLibrary: false
                ),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("""
            import fixture.Widget
            import fixture.render

            suspend fun Widget.probe() {
                render { left, right -> println(left + right) }
            }
            """.utf8))
            try index.inject(into: ctx)

            let facadePath = "<kswiftk-jvm-import>/fixture/ProviderKt.kt"
            let facadeID = try #require(ctx.sourceManager.fileID(forPath: facadePath))
            let facade = String(decoding: ctx.sourceManager.contents(of: facadeID), as: UTF8.self)
            #expect(facade.contains("suspend fun fixture.Widget.`render`"))
            #expect(facade.contains("(kotlin.Int, kotlin.Int) -> kotlin.Unit"))
            #expect(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/fixture/Widget.kt") != nil)
        }
    }

    // Room/KSP generated sources spell keyword package segments with
    // backticks (javax.`annotation`.processing.Generated); the lazy-class
    // scan must still see the reference and inject the classpath class.
    @Test
    func lazyClassInjectionSeesThroughBacktickedImportSegments() throws {
        try withWorkspace { root in
            try """
            package com.example.annotation

            class Widget
            """.write(to: root.appendingPathComponent("Widget.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Widget.kt", "-d", "widget.jar"], root: root)
            let widget = root.appendingPathComponent("widget.jar")
            let index = try JVMClasspathIndex.load(
                [widget.path], automaticLazyClasspathMemberLimit: 1
            )

            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "LazyBacktickImportTest",
                    inputs: [consumerPath],
                    outputPath: root.appendingPathComponent("out").path,
                    emit: .jvmJar,
                    target: .hostDefault(),
                    includeStdlib: false,
                    allowDefaultStdlibLibrary: false
                ),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("""
            package consumer

            import com.example.`annotation`.Widget

            fun probe(widget: Widget) {
                println(widget)
            }
            """.utf8))
            try index.inject(into: ctx)

            #expect(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/com/example/annotation/Widget.kt") != nil)
        }
    }

    // Escape-only dotted segments (e.g. "`.`." inside a string literal)
    // strip down to separators alone; the scan must skip them, not trap.
    @Test
    func lazyClassInjectionSkipsBacktickedEscapeOnlySegments() throws {
        try withWorkspace { root in
            try """
            package com.example.annotation

            class Widget
            """.write(to: root.appendingPathComponent("Widget.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Widget.kt", "-d", "widget.jar"], root: root)
            let widget = root.appendingPathComponent("widget.jar")
            let index = try JVMClasspathIndex.load(
                [widget.path], automaticLazyClasspathMemberLimit: 1
            )

            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "LazyBacktickEdgeTest",
                    inputs: [consumerPath],
                    outputPath: root.appendingPathComponent("out").path,
                    emit: .jvmJar,
                    target: .hostDefault(),
                    includeStdlib: false,
                    allowDefaultStdlibLibrary: false
                ),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            let degenerate = "`" + "." + "`" + "." + "`" + "." + "`"
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("""
            package consumer

            import com.example.`annotation`.Widget

            val marker = "\(degenerate)"

            fun probe(widget: Widget) {
                println(widget)
            }
            """.utf8))
            try index.inject(into: ctx)

            #expect(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/com/example/annotation/Widget.kt") != nil)
        }
    }
}
#endif
