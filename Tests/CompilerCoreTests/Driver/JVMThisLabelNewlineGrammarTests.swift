#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMThisLabelNewlineGrammarTests {
    // A newline before `@` starts an annotation on the next declaration, never a
    // label on the preceding `this` / `return` / `break` / `continue`. Compose's
    // ui-geometry sources rely on this (`= size * this` followed by
    // `@Stable fun Size.toRect()`), and kotlinc accepts all of these.
    @Test(arguments: [
        "class C { fun f(): C = this\n@Deprecated(\"x\") fun g(): Int = 1 }",
        "class C { val x: C get() = this\n@Suppress(\"x\") fun g(): Int = 1 }",
        "class C { fun f(): C { return this\n@Deprecated(\"x\") fun g(): Int = 1 } }",
        "fun f() { return\n@Suppress(\"x\") fun g() {} }",
        "fun f() { while (true) { break\n@Suppress(\"x\") fun g() {} } }",
        "fun f() { while (true) { continue\n@Suppress(\"x\") fun g() {} } }",
        "operator fun Float.times(s: Int) = s * this\n@Deprecated(\"x\") fun g(): Int = 1",
    ])
    func acceptsAnnotationAfterNewlineFollowingThisLikeKeyword(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "class C { fun f(): C = this@C\n@Deprecated(\"x\") fun g(): Int = 1 }",
        "fun f() { l@ while (true) { break@l\n@Suppress(\"x\") fun g() {} } }",
        "fun f() { return@f\n@Suppress(\"x\") fun g() {} }",
    ])
    func acceptsSameLineLabelsUnchanged(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}
#endif
