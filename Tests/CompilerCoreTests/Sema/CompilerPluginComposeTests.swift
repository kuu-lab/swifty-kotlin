#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CompilerPluginComposeTests {
    private let composeRuntimeStubs = """
    package androidx.compose.runtime

    @Target(
        AnnotationTarget.FUNCTION,
        AnnotationTarget.TYPE,
        AnnotationTarget.TYPE_PARAMETER,
        AnnotationTarget.PROPERTY,
        AnnotationTarget.PROPERTY_GETTER
    )
    annotation class Composable

    @Target(AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY_GETTER)
    annotation class ReadOnlyComposable

    @Target(AnnotationTarget.VALUE_PARAMETER, AnnotationTarget.TYPE)
    annotation class DisallowComposableCalls

    @Target(AnnotationTarget.CLASS)
    annotation class Stable

    @Target(AnnotationTarget.CLASS)
    annotation class Immutable

    interface Composer {
        fun record(tag: String)
    }

    val currentComposer: Composer?
        @Composable get() = null
    """

    @Test
    func composableFunctionsInjectComposerAndChangedParametersInKIR() throws {
        let userSource = """
        package com.example

        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.Composer
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.currentComposer

        @Stable
        class UiState(val label: String)

        @Composable
        fun Leaf(text: String) {
            currentComposer?.record(text)
        }

        @Composable
        fun Screen(state: UiState) {
            Leaf(state.label)
        }

        @Suppress("COMPOSABLE_INVOCATION")
        fun render(composer: Composer) {
            Screen(UiState("hello"))
        }
        """

        try withTemporaryFiles(contents: [composeRuntimeStubs, userSource]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToLowering(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            #expect(sema.composePluginEnabled)
            #expect(sema.composeComposerSymbol != nil)

            let leafSym = try #require(sema.symbols.lookup(fqName: [
                interner.intern("com"), interner.intern("example"), interner.intern("Leaf"),
            ]))
            let screenSym = try #require(sema.symbols.lookup(fqName: [
                interner.intern("com"), interner.intern("example"), interner.intern("Screen"),
            ]))
            let uiStateSym = try #require(sema.symbols.lookup(fqName: [
                interner.intern("com"), interner.intern("example"), interner.intern("UiState"),
            ]))
            #expect(sema.composableFunctions.contains(leafSym))
            #expect(sema.composableFunctions.contains(screenSym))
            #expect(sema.stableAnnotatedSymbols.contains(uiStateSym))

            let module = try #require(ctx.kir)
            let leafFunc = try #require(module.arena.function(for: leafSym))
            let screenFunc = try #require(module.arena.function(for: screenSym))

            // Original params (`text: String` / `state: UiState`) + `$composer: Composer?` + `$changed: Int`
            #expect(leafFunc.params.count == 3)
            #expect(screenFunc.params.count == 3)
            #expect(sema.symbols.symbol(leafFunc.params[1].symbol)?.name == interner.intern("$composer"))
            #expect(sema.symbols.symbol(leafFunc.params[2].symbol)?.name == interner.intern("$changed"))

            // Screen's call to Leaf receives the propagated `$composer` and `$changed` arguments (3 total args)
            let leafCall = screenFunc.body.first { instr in
                if case let .call(sym, _, _, _, _, _, _, _) = instr {
                    return sym == leafSym
                }
                return false
            }
            if case let .call(_, _, args, _, _, _, _, _) = leafCall {
                #expect(args.count == 3)
            } else {
                Issue.record("Expected lowered call from Screen to Leaf")
            }
        }
    }

    @Test
    func composableLambdaParameterAllowsNestedComposableCalls() throws {
        let userSource = """
        package com.example

        import androidx.compose.runtime.Composable

        @Composable
        fun Text(v: String) {}

        @Composable
        fun Column(content: @Composable () -> Unit) {
            content()
        }

        @Composable
        fun App() {
            Column {
                Text("ok")
            }
        }
        """

        try withTemporaryFiles(contents: [composeRuntimeStubs, userSource]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
        }
    }

    @Test
    func composableValidationDiagnostics() throws {
        let badSource = """
        package com.example

        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.DisallowComposableCalls
        import androidx.compose.runtime.ReadOnlyComposable

        @Composable
        fun Greeting() {}

        @Composable
        suspend fun badSuspend() {}

        @Composable
        fun main() {}

        @Composable
        var badVar: Int = 1

        @Composable
        val badBackingField: Int = 2

        fun nonComposableCaller() {
            Greeting()
        }

        @Composable
        @ReadOnlyComposable
        fun readOnlyCaller() {
            Greeting()
        }

        @Composable
        inline fun nonComposableSlot(block: @DisallowComposableCalls () -> Unit) {
            block()
        }

        @Composable
        fun disallowedUsage() {
            nonComposableSlot {
                Greeting()
            }
        }
        """

        try withTemporaryFiles(contents: [composeRuntimeStubs, badSource]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            let codes = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.code)
            #expect(codes.contains("KSWIFTK-SEMA-0490")) // @Composable suspend fun
            #expect(codes.contains("KSWIFTK-SEMA-0491")) // @Composable main
            #expect(codes.contains("KSWIFTK-SEMA-0492")) // @Composable var / backing field
            #expect(codes.contains("KSWIFTK-SEMA-0493")) // non-composable / @DisallowComposableCalls invocation
            #expect(codes.contains("KSWIFTK-SEMA-0494")) // non-readonly call inside @ReadOnlyComposable
        }
    }

    @Test
    func dynamicComposeCompilerPluginJarInspectionAndBridge() throws {
        let composeJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/compose-compiler-plugin.jar"
        guard FileManager.default.fileExists(atPath: composeJarPath),
              JvmPluginHostClient.shared.findJavaExecutable() != nil
        else { return }

        let inspection = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: composeJarPath)
        #expect(inspection.pluginId == "androidx.compose.compiler.plugins.kotlin")
        #expect(!inspection.options.isEmpty)

        let plan = try JvmPluginHostClient.shared.transformSema(
            pluginJarPath: composeJarPath,
            options: ["sourceInformation": ["true"]],
            classes: []
        )
        #expect(plan.composeEnabled == true)
    }
}
#endif
