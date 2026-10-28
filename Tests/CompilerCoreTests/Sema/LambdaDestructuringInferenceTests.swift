@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct LambdaDestructuringInferenceTests {
    @Test
    func singleComponentBindsExpectedType() throws {
        let sources = [
            """
            package singleList
            fun main() {
                val transform: (List<Int>) -> Int = { (a) -> a }
                println(transform(listOf(7, 8)))
            }
            """,
            """
            package singleCustom
            class Box(val value: Int) { operator fun component1(): Int = value }
            fun main() {
                val transform: (Box) -> Int = { (a) -> a }
                println(transform(Box(7)))
            }
            """,
            """
            package singleIgnored
            fun main() {
                val transform: (List<Int>) -> Int = { (_) -> 7 }
                println(transform(listOf(7, 8)))
            }
            """,
            """
            package singleMixed
            fun main() {
                val transform: (Int, List<Int>) -> Int = { acc, (a) -> acc + a }
                val reverse: (List<Int>, Int) -> Int = { (a), acc -> a + acc }
                println(transform(1, listOf(7)))
                println(reverse(listOf(7), 1))
            }
            """,
            """
            package singleAnnotated
            fun main() {
                val transform = { (a): List<Int> -> a }
                val mixed = { acc: Int, (a): List<Int> -> acc + a }
                println(transform(listOf(7)))
                println(mixed(1, listOf(7)))
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for (index, path) in paths.enumerated() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(sources[index]): \(errors)")
                if index == 2 { continue }
                let refs = allExprIDs(in: ast, path: path, ctx: ctx) { _, expression in
                    guard case let .nameRef(name, _) = expression else { return false }
                    return ctx.interner.resolve(name) == "a"
                }
                let types = refs.compactMap { sema.bindings.exprType(for: $0) }
                #expect(!types.isEmpty)
                #expect(types.allSatisfy { $0 == sema.types.intType })
            }
        }
    }

    @Test
    func suspendLambdaSquareBracketDestructuringBindsComponents() throws {
        let source = """
        data class A(val o: String) {
            operator fun component2(): String = "K"
        }
        fun builder(c: suspend (A) -> Unit) {}
        fun run(): String {
            var result = ""
            builder { [x, y] -> result = x + y }
            return result
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let references = allExprIDs(in: ast, path: path, ctx: ctx) { _, expression in
                guard case let .nameRef(name, _) = expression else { return false }
                return ["x", "y"].contains(ctx.interner.resolve(name))
            }
            var checked: Set<String> = []
            for id in references {
                guard case let .nameRef(name, _)? = ast.arena.expr(id),
                      let type = sema.bindings.exprType(for: id)
                else { continue }
                let nameText = ctx.interner.resolve(name)
                #expect(type == sema.types.stringType)
                checked.insert(nameText)
            }
            #expect(checked == ["x", "y"])
        }
    }

    @Test
    func runningFoldBindsSecondParameterComponents() throws {
        let source = """
        data class Point(val x:Int){operator fun plus(p:Point)=Point(x+p.x);operator fun times(n:Int)=Point(x*n)}
        fun main(){println(listOf(Point(2) to 3).runningFold(Point(0)){acc,(direction,distance)->acc+direction*distance}.last().x)}
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let point = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Point")]).first {
                sema.symbols.symbol($0)?.kind == .class
            })
            var checked: Set<String> = []
            let references = allExprIDs(in: ast, path: paths[0], ctx: ctx) { _, expression in
                guard case let .nameRef(name, _) = expression else { return false }
                return ["direction", "distance"].contains(ctx.interner.resolve(name))
            }
            for id in references {
                guard case let .nameRef(name, _)? = ast.arena.expr(id) else { continue }
                let text = ctx.interner.resolve(name)
                guard text == "direction" || text == "distance" else { continue }
                // Speculative parsing can leave unbound expressions in the arena.
                guard let type = sema.bindings.exprType(for: id) else { continue }
                if text == "distance" {
                    #expect(type == sema.types.intType)
                } else {
                    guard case let .classType(classType) = sema.types.kind(of: type) else {
                        Issue.record("direction must have type Point")
                        continue
                    }
                    #expect(classType.classSymbol == point)
                }
                checked.insert(text)
            }
            #expect(checked == ["direction", "distance"])
        }
    }

    @Test
    func completeNameBasedDestructuringBindsLambdaParameterProperties() throws {
        let source = """
        class Point(val first: Int, val second: Int)
        fun transform(point: Point): Int {
            val combine: (Point) -> Int = { (first, second) -> first + second }
            return combine(point)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["name-based-destructuring=complete"],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let sourceDiagnostics = diagnosticsForPath(path, in: ctx)
            #expect(!sourceDiagnostics.hasError, "Unexpected diagnostics: \(sourceDiagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let declarationIndex = try #require(ast.arena.exprs.indices.first { index in
                if case .destructuringDecl = ast.arena.exprs[index] { return true }
                return false
            })
            let declarationID = ExprID(rawValue: Int32(declarationIndex))
            #expect(sema.bindings.destructuringProperty(for: declarationID, index: 0) != nil)
            #expect(sema.bindings.destructuringProperty(for: declarationID, index: 1) != nil)
        }
    }

    @Test
    func acceptsMixedDestructuring() throws {
        let expressions = [
            "listOf(2 to 3).runningFold(0) { acc, (_, value) -> acc + value }",
            "listOf(2 to 3).runningFold(0) { acc, (value, _) -> acc + value }",
            "listOf(2 to 3).runningFold(0) { acc, (_, _) -> acc + 1 }",
            "listOf(2 to 3).fold(0) { acc, (first, second) -> acc + first * second }",
            "listOf(2 to 3).foldRight(0) { (first, second), acc -> acc + first * second }",
            "listOf(2 to 3).forEachIndexed { index, (first, second) -> println(index + first * second) }",
            "listOf(2 to 3).zip(listOf(4 to 5)) { (a, b), (c, d) -> a * b + c * d }",
            "listOf(2 to 3).fold(0) { acc: Int, (first, second): Pair<Int, Int> -> acc + first * second }",
            "listOf(2 to 3).fold(0) { __destructured_1, (first, second) -> __destructured_1 + first + second }",
            "listOf(2 to 3).zip(listOf(4 to 5)) { (__destructured_1, b), (c, d) -> __destructured_1 + b + c + d }",
        ]
        let sources = expressions.enumerated().map { index, expression in
            "package sample\(index)\nfun main() { println(\(expression)) }"
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for (index, path) in paths.enumerated() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(expressions[index]): \(errors)")
            }
        }
    }

    @Test
    func rejectsInvalidComponents() throws {
        let cases = [
            ("listOf(2).forEach { (first) -> println(first) }", ["KSWIFTK-SEMA-0086"]),
            ("listOf(listOf(2)).forEach { (first): List<String> -> println(first) }", ["KSWIFTK-SEMA-0025"]),
            ("listOf(2 to 3).fold(0) { acc, (first, second, third) -> acc + third }", ["KSWIFTK-SEMA-0086"]),
            ("listOf(2).fold(0) { acc, (first, second) -> acc + first }", ["KSWIFTK-SEMA-0086"]),
            ("listOf(2 to 3).fold(0) { acc, (first, _) -> acc + second }", ["KSWIFTK-SEMA-0022"]),
            ("listOf(2 to 3).fold(0) { acc, (first, second): Pair<String, Int> -> acc + first.length + second }", ["KSWIFTK-SEMA-0025", "KSWIFTK-SEMA-0002"]),
        ]
        let sources = cases.enumerated().map { index, testCase in
            "package sample\(index)\nfun main() { println(\(testCase.0)) }"
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for (index, path) in paths.enumerated() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.contains { cases[index].1.contains($0.code) }, "\(cases[index].0): \(errors)")
            }
        }
    }
}
