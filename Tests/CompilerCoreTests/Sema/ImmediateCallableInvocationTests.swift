@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ImmediateCallableInvocationTests {
    @Test func callableArgumentsUseExpectedIntegerLiteralTypes() throws {
        let ctx = makeContextFromSource("""
        class Holder(val f: (Byte) -> Int)
        fun parity() {
            val byte: (Byte) -> Int = { 0 }
            val short: (Short) -> Int = { 0 }
            val long: (Long) -> Int = { 0 }
            val unsigned: (UShort) -> Int = { 0 }
            byte(-128)
            byte.invoke(127)
            short(-32768)
            long(1)
            unsigned(65535u)
            Holder(byte).f(-1)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let getterContext = annotatedContextPropertyCompilation()
        try runSema(getterContext)
        #expect(!getterContext.diagnostics.hasError, "\(getterContext.diagnostics.diagnostics)")
        let ast = try #require(getterContext.ast)
        let sema = try #require(getterContext.sema)
        let expectedTypes = ["SegmentReadContextImpl": "SegmentReadContext",
            "SegmentWriteContextImpl": "SegmentWriteContext",
            "BufferIterationContextImpl": "BufferIterationContext"]
        var propertyCount = 0
        for declaration in ast.arena.decls {
            guard case let .propertyDecl(property) = declaration,
                  let expectedName = expectedTypes[getterContext.interner.resolve(property.name)] else { continue }
            propertyCount += 1
            let type = try #require(property.type.flatMap { ast.arena.typeRef($0) })
            guard case let .named(path, arguments, nullable) = type else {
                Issue.record("The property type must remain the declared interface")
                continue
            }
            #expect(path.map { getterContext.interner.resolve($0) } == [expectedName])
            #expect(arguments.isEmpty && !nullable)
            #expect(property.getter?.body != nil && property.getter?.body != .unit)
            #expect((property.annotations + (property.getter?.annotations ?? [])).contains {
                $0.name == "kotlin.jvm.JvmSynthetic" && $0.useSiteTarget == "get"
            })
            let fqName = ["kotlinx", "io", "unsafe", getterContext.interner.resolve(property.name)]
                .map { getterContext.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookup(fqName: fqName))
            let semanticType = try #require(sema.symbols.propertyType(for: symbol))
            guard case let .classType(classType) = sema.types.kind(of: semanticType),
                  let classifier = sema.symbols.symbol(classType.classSymbol) else {
                Issue.record("The callable argument must carry the interface's nominal type")
                continue
            }
            #expect(getterContext.interner.resolve(classifier.name) == expectedName)
        }
        #expect(propertyCount == 3)
        let outProperty = try #require(ast.arena.decls.compactMap { declaration -> PropertyDecl? in
            guard case let .propertyDecl(property) = declaration,
                  getterContext.interner.resolve(property.name) == "out" else { return nil }
            return property
        }.first)
        let outType = try #require(outProperty.type.flatMap { ast.arena.typeRef($0) })
        guard case let .named(outPath, outArguments, outNullable) = outType else {
            Issue.record("A soft-keyword property name must retain its explicit type")
            return
        }
        #expect(outPath.map { getterContext.interner.resolve($0) } == ["Long"])
        #expect(outArguments.isEmpty && !outNullable)
    }

    @Test func callableArgumentsDoNotCoerceNonLiteralsOrOutOfRangeValues() throws {
        let ctx = makeContextFromSource("""
        fun parity(value: Int) {
            val byte: (Byte) -> Int = { 0 }
            byte(128)
            byte(-129)
            byte(value)
            byte(1L)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.count == 4)

        let getterContext = annotatedContextPropertyCompilation(includeWrongArgument: true)
        try runSema(getterContext)
        let errors = getterContext.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1 && errors.first?.code == "KSWIFTK-TYPE-0001",
            "Getter typing must not accept an unrelated Int: \(errors)")
        let range = try #require(errors.first?.primaryRange)
        #expect(getterContext.sourceManager.slice(range) == "17")
    }

    @Test(arguments: [
        "fun main() { val value: Int = with(1) { { 2 } }() }",
        "val value: Int = with(1) { { 2 } }()",
        "fun value(): Int = with(1) { { 2 } }()",
    ])
    func trailingLambdaInvocationIsPreservedInDeclaration(source: String) throws {
        let (ast, _) = try buildASTModule(from: source, includeStdlib: false)
        let invocations = ast.arena.exprs.filter { expr in
            guard case let .call(callee, _, args, _) = expr,
                  args.isEmpty,
                  case let .call(_, _, innerArgs, _) = ast.arena.expr(callee)
            else {
                return false
            }
            return innerArgs.count == 2
        }
        #expect(invocations.count == 1)
    }

    @Test func parenthesizedExpressionOnNextLineRemainsSeparate() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun main() {
            val value = with(1) { 2 }
            (3)
        }
        """, includeStdlib: false)
        let main = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = main.body else {
            Issue.record("Expected a block body")
            return
        }
        #expect(statements.count == 2)
        guard case .intLiteral(3, _) = ast.arena.expr(try #require(statements.last)) else {
            Issue.record("Expected the next-line expression to remain a separate statement")
            return
        }
    }

    @Test func genericCallReturningLambdaDoesNotReceiveInvocationResultType() throws {
        let ctx = makeContextFromSources([
            """
            fun main() {
                val value: Int = with(1) { { 2 } }()
                println(value)
            }
            """
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let main = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = main.body,
              let declaration = statements.first,
              case let .localDecl(_, _, _, initializer?, _, _, _) = ast.arena.expr(declaration),
              case let .call(callee, _, args, _) = ast.arena.expr(initializer),
              case .call = ast.arena.expr(callee)
        else {
            Issue.record("Expected a local initializer invoking the result of with")
            return
        }
        #expect(args.isEmpty)
        #expect(sema.bindings.exprType(for: initializer) == sema.types.intType)
        let calleeType = try #require(sema.bindings.exprType(for: callee))
        guard case let .functionType(functionType) = sema.types.kind(of: calleeType) else {
            Issue.record("Expected with to return a function value")
            return
        }
        #expect(functionType.params.isEmpty)
        #expect(functionType.returnType == sema.types.intType)
    }

    @Test func immediateInvocationInGenericAndDeclarationContexts() throws {
        let ctx = makeContextFromSources([
            """
            fun <T> identity(value: T): T = value
            val topLevel: Int = with(1) { { 3 } }()
            fun expressionBody(): Int = with(1) { { 4 } }()
            fun main() {
                val withArgument: Int = with(1) { { x: Int -> x + 1 } }(6)
                val identityResult: Int = identity { 5 }()
                val runResult: Int = run { { 6 } }()
                val memberResult: Int = 1.let { { 7 } }()
                val stored: () -> Int = with(1) { { 8 } }
                val storedResult: Int = stored()
                val nonFunction: Int = with(1) { 9 }
                val direct: Int = { 10 }()
            }
            """
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func invocationResultStillMustMatchExpectedType() throws {
        let ctx = makeContextFromSources([
            """
            fun main() {
                val value: String = with(1) { { 2 } }()
            }
            """
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    private func annotatedContextPropertyCompilation(includeWrongArgument: Bool = false) -> CompilationContext {
        let positiveSource = """
        package kotlinx.io.unsafe

        import kotlin.PublishedApi

        annotation class UnsafeIoApi

        class Segment(val next: Segment? = null)

        @UnsafeIoApi
        object UnsafeShape {
            fun readFromHead(head: Segment, readAction: (SegmentReadContext, Segment) -> Int): Int =
                readAction(SegmentReadContextImpl, head)
            fun writeToTail(tail: Segment, writeAction: (SegmentWriteContext, Segment) -> Int): Int =
                writeAction(SegmentWriteContextImpl, tail)
            fun iterate(head: Segment?, iterationAction: (BufferIterationContext, Segment?) -> Unit) {
                iterationAction(BufferIterationContextImpl, head)
            }
            fun iterateAt(s: Segment?, o: Long, iterationAction: (BufferIterationContext, Segment?, Long) -> Unit) {
                iterationAction(BufferIterationContextImpl, s, o)
            }
            fun each(first: Segment?, action: (SegmentReadContext, Segment) -> Unit) {
                var curr: Segment? = first
                while (curr != null) {
                    action(SegmentReadContextImpl, curr)
                    curr = curr.next
                }
            }
        }

        @UnsafeIoApi
        interface SegmentReadContext {}
        @UnsafeIoApi
        interface SegmentWriteContext {}
        @UnsafeIoApi
        interface BufferIterationContext : SegmentReadContext {}

        @UnsafeIoApi
        @PublishedApi
        @get:kotlin.jvm.JvmSynthetic
        internal val SegmentReadContextImpl: SegmentReadContext
            get() = SegmentReadContextSingleton
        private object SegmentReadContextSingleton : SegmentReadContext {}

        @UnsafeIoApi
        @PublishedApi
        @get:kotlin.jvm.JvmSynthetic
        internal val SegmentWriteContextImpl: SegmentWriteContext
            get() = SegmentWriteContextSingleton
        private object SegmentWriteContextSingleton : SegmentWriteContext {}

        @UnsafeIoApi
        @PublishedApi
        @get:kotlin.jvm.JvmSynthetic
        internal val BufferIterationContextImpl: BufferIterationContext
            get() = BufferIterationContextSingleton
        private object BufferIterationContextSingleton : BufferIterationContext {}

        public val out: Long get() = 1
        """
        let wrongSource = """
        fun rejectUnrelated(action: (SegmentReadContext, Segment) -> Int, segment: Segment): Int =
            action(17, segment)
        """
        let sources = [
            "package kotlin.jvm\nannotation class JvmSynthetic",
            "package kotlin\nannotation class PublishedApi",
            positiveSource + (includeWrongArgument ? "\n" + wrongSource : ""),
        ]
        let paths = sources.indices.map { "/annotated-getter/part\($0).kt" }
        let context = makeCompilationContext(inputs: paths, includeStdlib: false)
        for (path, contents) in zip(paths, sources) {
            _ = context.sourceManager.addFile(path: path, contents: Data(contents.utf8))
        }
        return context
    }
}
