@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CrossFileCompanionPropertyInferenceTests {
    // Unchanged Point2D.kt from tginsberg/advent-2023-kotlin, revision
    // 0d5732508025a7e340366594c879b99fe6e7cbf0, plus the KUU-1921 consumer.
    private static let pointSource = """
    package com.ginsberg.advent2023

    import kotlin.math.absoluteValue

    data class Point2D(val x: Int, val y: Int) {
        fun neighbors(): Set<Point2D> =
            setOf(
                this + NORTH_WEST,
                this + NORTH,
                this + NORTH_EAST,
                this + WEST,
                this + EAST,
                this + SOUTH_WEST,
                this + SOUTH,
                this + SOUTH_EAST
            )

        fun cardinalNeighbors(): Set<Point2D> =
            setOf(
                this + NORTH,
                this + EAST,
                this + SOUTH,
                this + WEST
            )

        fun distanceTo(other: Point2D): Int =
            (x - other.x).absoluteValue + (y - other.y).absoluteValue

        operator fun minus(other: Point2D): Point2D =
            Point2D(x - other.x, y - other.y)

        operator fun plus(other: Point2D): Point2D =
            Point2D(x + other.x, y + other.y)

        operator fun times(amount: Int): Point2D =
            Point2D(x * amount, y * amount)

        companion object {
            val ORIGIN = Point2D(0, 0)
            val NORTH = Point2D(0, -1)
            val EAST = Point2D(1, 0)
            val SOUTH = Point2D(0, 1)
            val WEST = Point2D(-1, 0)
            val NORTH_WEST = NORTH + WEST
            val NORTH_EAST = NORTH + EAST
            val SOUTH_WEST = SOUTH + WEST
            val SOUTH_EAST = SOUTH + EAST
        }
    }
    """.replacingOccurrences(of: "\n", with: "\r\n")
    private static let consumerSource = """
    import com.ginsberg.advent2023.Point2D
    class Solver {private val moves:Map<Pair<Char,Point2D>,Point2D> = mapOf(('|' to Point2D.NORTH) to Point2D.NORTH,('-' to Point2D.EAST) to Point2D.EAST);fun count()=moves.size}
    fun main(){println(Solver().count())}
    """ + "\n"

    @Test(arguments: [true, false])
    func pointMapKeepsNominalCompanionTypesInEitherFileOrder(consumerFirst: Bool) throws {
        let sources = consumerFirst
            ? [Self.consumerSource, Self.pointSource]
            : [Self.pointSource, Self.consumerSource]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let point = try #require(sema.symbols.lookup(
            fqName: ["com", "ginsberg", "advent2023", "Point2D"].map(ctx.interner.intern)
        ))
        let pointType = sema.types.make(.classType(ClassType(
            classSymbol: point, args: [], nullability: .nonNull
        )))
        let companion = try #require(sema.symbols.companionObjectSymbol(for: point))
        let companionName = try #require(sema.symbols.symbol(companion)).fqName
        for name in ["ORIGIN", "NORTH", "EAST", "SOUTH", "WEST"] {
            let property = try #require(sema.symbols.lookup(
                fqName: companionName + [ctx.interner.intern(name)]
            ))
            #expect(sema.symbols.propertyType(for: property) == pointType)
        }
        let consumerFile = try #require(ast.files.first { $0.packageFQName.isEmpty })
        let directions = Set(["NORTH", "EAST"].map(ctx.interner.intern))
        let references = sema.bindings.exprTypes.keys.filter { exprID in
            guard ast.arena.exprRange(exprID)?.start.file == consumerFile.fileID,
                  case let .memberCall(_, name, _, _, _)? = ast.arena.expr(exprID)
            else { return false }
            return directions.contains(name) && !ast.arena.isExplicitCall(exprID)
        }
        #expect(references.count == 4)
        for reference in references {
            #expect(sema.bindings.exprType(for: reference) == pointType)
        }
    }

    @Test(arguments: [true, false])
    func namedNestedCompanionUsesItsOwnScope(consumerFirst: Bool) throws {
        let use = """
        package consumer
        import model.Outer
        fun direction(): Outer.Point = Outer.Point.UP
        """
        let declarations = """
        package model
        class Outer {
            class Point(val x: Int, val y: Int) {
                companion object Directions {
                    private val offset = -1
                    val UP = Point(y = offset, x = 0)
                }
            }
        }
        """
        let sources = consumerFirst ? [use, declarations] : [declarations, use]
        _ = try SemaFixture(surface: "nested named companion inference across files").make(sources: sources)
    }

    @Test
    func nonInnerNestedPropertyDoesNotCaptureAnInheritedOuterReceiver() throws {
        let source = """
        val offset: Int = 1
        open class Base { val offset: String = "outer" }
        class Outer : Base() {
            class Nested { val value = offset }
        }
        fun value(): Int = Outer.Nested().value
        """
        let (sema, interner) = try SemaFixture(surface: "static nested property receiver scope").make(source: source)
        let property = try #require(sema.symbols.lookup(
            fqName: ["Outer", "Nested", "value"].map(interner.intern)
        ))
        #expect(sema.symbols.propertyType(for: property) == sema.types.intType)
    }

    @Test
    func inheritedUnresolvedMemberDoesNotUseATopLevelNamesType() throws {
        let source = """
        val offset: Int = 1
        open class Base { val offset = if (true) "north" else "south" }
        object Directions : Base() { val value = offset }
        fun value(): String = Directions.value
        """
        let (sema, interner) = try SemaFixture(surface: "unresolved inherited property precheck").make(source: source)
        let property = try #require(sema.symbols.lookup(
            fqName: ["Directions", "value"].map(interner.intern)
        ))
        #expect(sema.symbols.propertyType(for: property) == sema.types.stringType)
    }

    @Test(arguments: [true, false])
    func wrongCompanionTypeStillReportsAnError(consumerFirst: Bool) throws {
        let use = """
        import model.Point
        fun direction(): String = Point.UP
        """
        let declarations = """
        package model
        class Point(val x: Int, val y: Int) {
            companion object { val UP = Point(0, -1) }
        }
        """
        let sources = consumerFirst ? [use, declarations] : [declarations, use]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test(arguments: [true, false])
    func invalidCompanionConstructorArgumentsKeepTheirDiagnostic(consumerFirst: Bool) throws {
        let use = """
        import model.Point
        fun direction(): Point = Point.UP
        """
        let declarations = """
        package model
        class Point(val x: Int, val y: Int) {
            companion object { val UP = Point("north", 0) }
        }
        """
        let sources = consumerFirst ? [use, declarations] : [declarations, use]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        let ast = try #require(ctx.ast)
        let declarationFile = try #require(ast.files.first {
            $0.packageFQName == [ctx.interner.intern("model")]
        })
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.primaryRange?.start.file == declarationFile.fileID
        })
    }

    @Test(arguments: [true, false])
    func cyclicCompanionPropertiesDoNotFabricateAnIntegerType(consumerFirst: Bool) throws {
        let use = """
        import model.Point
        fun direction(): Int = Point.FIRST
        """
        let declarations = """
        package model
        class Point {
            companion object {
                val FIRST = SECOND
                val SECOND = FIRST
            }
        }
        """
        let sources = consumerFirst ? [use, declarations] : [declarations, use]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
        let sema = try #require(ctx.sema)
        for name in ["FIRST", "SECOND"] {
            let property = try #require(sema.symbols.lookup(
                fqName: ["model", "Point", "Companion", name].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.propertyType(for: property) != sema.types.intType)
        }
    }
}
