@testable import CompilerCore
import Testing

@Suite
struct VarargTrailingLambdaResolutionTests {
    @Test(arguments: [
        "build { value = 17 }", "build(1) { value = 23 }",
        "build(1, 2, 3) { value = 31 }", "build(action = { value = 37 })",
        "build(1, action = { value = 41 })",
    ])
    func omittedAndMultipleVarargsContextualizeReceiver(call: String) throws {
        let ctx = makeContextFromSource("""
        class Builder { var value: Int = 0 }
        fun build(vararg values: Int, action: Builder.() -> Unit = {}): Int {
            val builder = Builder()
            builder.action()
            return builder.value
        }
        fun use() = \(call)
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func namedRequiredParameterAndDefaultsDoNotBlockTrailingLambda() throws {
        let ctx = makeContextFromSource("""
        class Builder { var value: Int = 0 }
        fun build(vararg values: Int, tag: String, option: Int = 0, action: Builder.() -> Unit = {}): Int = 0
        fun prefix(tag: String = "default", vararg values: Int, action: Builder.() -> Unit = {}): Int = 0
        fun use() {
            build(1, tag = "x") { value = 17 }
            build(tag = "x") { value = 23 }
            prefix { value = 31 }
            prefix("x", 1, 2, 3) { value = 37 }
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func memberAndSafeMemberUseTrailingParameter() throws {
        let ctx = makeContextFromSource("""
        class Builder { var value: Int = 0 }
        class Host {
            fun build(vararg values: Int, action: Builder.() -> Unit = {}): Int = 0
        }
        fun use(host: Host, nullable: Host?) {
            host.build { value = 17 }
            host.build(1, 2, 3) { value = 23 }
            nullable?.build { value = 31 }
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func multipleVarargsNarrowOverloadedTypedLambda() throws {
        let ctx = makeContextFromSource("""
        class Builder { var value: Int = 0 }
        fun pick(vararg values: Int, action: Builder.(Int) -> Unit = {}): Int = 0
        fun pick(vararg values: String, action: Builder.(String) -> Unit = {}): Int = 0
        fun use() = pick(1, 2, 3) { n: Int -> value = n }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func genericLastParameterStillAcceptsTrailingLambda() throws {
        let ctx = makeContextFromSource("""
        fun <T> identity(value: T): T = value
        fun use() { identity { 17 } }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func trailingSAMLambdaUsesSyntaxAfterNominalConversion() throws {
        let ctx = makeContextFromSource("""
        fun interface Action { fun run() }
        fun apply(action: Action) = action.run()
        fun varargs(vararg values: Int, action: Action) = action.run()
        class Host { fun apply(action: Action) = action.run() }
        fun use(host: Host, nullable: Host?) {
            apply {}
            varargs {}
            varargs(1, 2, 3) {}
            host.apply {}
            nullable?.apply {}
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func sourceFunctionVarargAndTrailingLambdaHaveDifferentMappings(trailingFirst: Bool) throws {
        let calls = trailingFirst ? "actions {}; actions({})" : "actions({}); actions {}"
        let ctx = makeContextFromSource("""
        fun actions(vararg items: () -> Unit, action: () -> Unit = {}) {}
        fun use() { \(calls) }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var mappings: [[Int: Int]] = []
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, _, _) = ast.arena.expr(id),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(name) == "actions" else { continue }
            mappings.append(try #require(sema.bindings.callBinding(for: id)).parameterMapping)
        }
        #expect(mappings == (trailingFirst ? [[0: 1], [0: 0]] : [[0: 0], [0: 1]]))
    }

    @Test(arguments: ["build({ value = 17 })", "build(1, { value = 17 })",
                      "build(1, 2, 3, { value = 17 })"])
    func parenthesizedLambdaRemainsVarargElement(call: String) throws {
        let ctx = makeContextFromSource("""
        class Builder { var value: Int = 0 }
        fun build(vararg values: Int, action: Builder.() -> Unit = {}): Int = 0
        fun use() = \(call)
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected \(call) to be rejected")
    }

    @Test(arguments: [
        "fun invalid(vararg xs: Int, action: Builder.() -> Unit = {}, suffix: Int = 0) = 0",
        "fun invalid(vararg actions: Builder.() -> Unit) = 0",
        "fun invalid(vararg xs: Int, tag: String, action: Builder.() -> Unit = {}) = 0",
    ])
    func trailingLambdaCannotSkipLastParameterOrRequiredArgument(declaration: String) throws {
        let ctx = makeContextFromSource("""
        class Builder { var value: Int = 0 }
        \(declaration)
        fun use() = invalid { value = 17 }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected invalid trailing lambda to be rejected")
    }
}

extension SemaCacheContextTests {
    @Test(arguments: [false, true])
    func trailingLambdaPositionSeparatesCacheEntries(trailingFirst: Bool) {
        let setup = makeSemaModule()
        let name = setup.interner.intern("actions")
        let functionType = setup.types.make(.functionType(FunctionType(
            params: [], returnType: setup.types.unitType
        )))
        let function = setup.symbols.define(
            kind: .function, name: name, fqName: [name], declSite: nil,
            visibility: .public, flags: []
        )
        setup.symbols.setFunctionSignature(FunctionSignature(
            parameterTypes: [functionType, functionType], returnType: setup.types.unitType,
            valueParameterHasDefaultValues: [false, true], valueParameterIsVararg: [true, false]
        ), for: function)
        let cache = SemaCacheContext()
        let resolver = OverloadResolver()
        resolver.cacheContext = cache
        for trailing in [trailingFirst, !trailingFirst, trailingFirst, !trailingFirst] {
            let resolved = resolver.resolveCall(
                candidates: [function],
                call: CallExpr(range: makeRange(start: 0, end: 10), calleeName: name,
                               args: [CallArg(type: functionType, isTrailingLambda: trailing)]),
                expectedType: nil, ctx: setup.ctx
            )
            #expect(resolved.diagnostic == nil)
            #expect(resolved.parameterMapping == [0: trailing ? 1 : 0])
        }
        #expect(cache.callResolutionMisses == 2)
        #expect(cache.callResolutionHits == 2)
        // Candidate-specific lambda typing replaces Any with the function type;
        // it must retain the argument's syntactic position too.
        for trailing in [false, true] {
            let resolved = resolver.resolveCall(
                candidates: [function],
                call: CallExpr(range: makeRange(start: 20, end: 30), calleeName: name,
                               args: [CallArg(type: setup.types.anyType, isTrailingLambda: trailing)]),
                expectedType: nil, candidateArgumentTypes: [function: [0: functionType]], ctx: setup.ctx
            )
            #expect(resolved.diagnostic == nil)
            #expect(resolved.parameterMapping == [0: trailing ? 1 : 0])
        }
    }
}
