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

            suspend fun <T> run(scope: Scope, block: suspend Scope.() -> T): T = TODO()
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
        }
    }
}
#endif
