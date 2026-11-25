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

    @Test
    func suspendFunctionTypeParameterRendersKotlinFunctionType() throws {
        try withWorkspace { root in
            // kotlinx-coroutines-style multifile facade: the erased
            // kotlin.jvm.functions.FunctionN carrier has no Kotlin
            // declaration, so the suspend metadata path must render the
            // function type (and declare its type parameters) itself.
            try """
            @file:JvmMultifileClass
            @file:JvmName("ProviderKt")
            package fixture

            class Scope
            """.write(to: root.appendingPathComponent("A.kt"), atomically: true, encoding: .utf8)
            try """
            @file:JvmMultifileClass
            @file:JvmName("ProviderKt")
            package fixture

            interface Marker

            suspend fun <T> run(scope: Scope, block: suspend Scope.() -> T): T = TODO()

            suspend fun <T : Marker> ping(value: T): T = value

            suspend fun <T : Comparable<R>, R> compare(left: () -> T, right: () -> R): Int = 0
            """.write(to: root.appendingPathComponent("B.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["A.kt", "B.kt", "-d", "provider.jar"], root: root)
            let provider = root.appendingPathComponent("provider.jar")
            let index = try JVMClasspathIndex.load([provider.path])

            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "SuspendFunctionTypeTest",
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
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("fun main() {}".utf8))
            try index.inject(into: ctx)

            let facadePath = "<kswiftk-jvm-import>/fixture/ProviderKt.kt"
            let facadeID = try #require(ctx.sourceManager.fileID(forPath: facadePath))
            let facade = String(decoding: ctx.sourceManager.contents(of: facadeID), as: UTF8.self)
            #expect(!facade.contains("kotlin.jvm.functions.Function"))
            #expect(facade.contains("<`T`>"))
            #expect(facade.contains("): `T`"))
            // Bare type-parameter parameters keep their Kotlin type.
            #expect(facade.contains("`value`: `T`"))
            // Bounds render in a where clause, including bounds that
            // reference a later type parameter.
            #expect(facade.contains("where `T`: fixture.Marker"))
            #expect(facade.contains("kotlin.Comparable<`R`>"))
        }
    }

    @Test
    func lazyMultifileSuspendTypeParameterBoundsJoinClosure() throws {
        try withWorkspace { root in
            // `Marker` appears only in ping's type-parameter bound, which the
            // erased JVM signature does not carry; lazy injection must still
            // pull it in or the emitted where clause is unresolved.
            try """
            @file:JvmMultifileClass
            @file:JvmName("ProviderKt")
            package fixture

            interface Marker
            """.write(to: root.appendingPathComponent("A.kt"), atomically: true, encoding: .utf8)
            try """
            @file:JvmMultifileClass
            @file:JvmName("ProviderKt")
            package fixture

            suspend fun <T : Marker> ping(value: T): T = value

            fun answer(): Int = 42
            """.write(to: root.appendingPathComponent("B.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["A.kt", "B.kt", "-d", "provider.jar"], root: root)
            let provider = root.appendingPathComponent("provider.jar")
            let index = try JVMClasspathIndex.load(
                [provider.path], automaticLazyClasspathMemberLimit: 1
            )
            #expect(index.lazyClassNames.contains("fixture/ProviderKt"))
            #expect(index.lazyClassNames.contains("fixture/Marker"))

            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "LazySuspendBoundsTest",
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
            import fixture.answer

            fun main() { println(answer()) }
            """.utf8))
            try index.inject(into: ctx)

            let facadePath = "<kswiftk-jvm-import>/fixture/ProviderKt.kt"
            let facadeID = try #require(ctx.sourceManager.fileID(forPath: facadePath))
            let facade = String(decoding: ctx.sourceManager.contents(of: facadeID), as: UTF8.self)
            #expect(facade.contains("where `T`: fixture.Marker"))
            #expect(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/fixture/Marker.kt") != nil)
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
