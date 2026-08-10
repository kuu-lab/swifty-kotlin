#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RangeSyntheticMemberLinkTests {

    private func functionDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> FunDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard case let .funDecl(function) = ast.arena.decl(declID),
                      interner.resolve(function.name) == name
                else { continue }
                return function
            }
        }
        return nil
    }

    private func bodyRange(of function: FunDecl) -> SourceRange? {
        switch function.body {
        case .block(_, let range), .expr(_, let range):
            return range
        case .unit:
            return nil
        }
    }

    private func firstCallExpr(
        named callName: String,
        in function: FunDecl,
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        guard let functionBodyRange = bodyRange(of: function) else { return nil }
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let exprRange = ast.arena.exprRange(exprID),
                  functionBodyRange.contains(exprRange)
            else { continue }

            let matches: Bool
            switch expr {
            case let .call(calleeExpr, _, _, _):
                guard case let .nameRef(callee, _) = ast.arena.expr(calleeExpr) else { continue }
                matches = interner.resolve(callee) == callName
            case let .memberCall(_, callee, _, _, _):
                matches = interner.resolve(callee) == callName
            default:
                continue
            }
            if matches { return exprID }
        }
        return nil
    }

    private func externalLink(
        for owner: String,
        member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "ranges", owner, member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else {
            return nil
        }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func functionExternalLink(
        for owner: String,
        member: String,
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "ranges", owner, member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes.count == parameterCount
        }.flatMap { sema.symbols.externalLinkName(for: $0) }
    }

    @Test func testRangeSyntheticLinksAndCallBindings() throws {
        let source = """
        import kotlin.ranges.*

        fun intProbe(range: IntRange): Int = range.random()
        fun longProbe(range: LongRange): Long = range.random()
        fun charProbe(range: CharRange): Char = range.random()
        fun uintProbe(range: UIntRange): UInt = range.random()
        fun ulongProbe(range: ULongRange): ULong = range.random()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let interner = ctx.interner

        // MARK: - CharProgression synthetic surface

        let charProgressionFQName = ["kotlin", "ranges", "CharProgression"].map { interner.intern($0) }
        let charProgressionSymbol = try #require(sema.symbols.lookup(fqName: charProgressionFQName))
        let charProgressionType = sema.types.make(.classType(ClassType(
            classSymbol: charProgressionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: charProgressionSymbol))
        let companionInfo = try #require(sema.symbols.symbol(companionSymbol))
        let fromClosedRangeSymbol = try #require(
            sema.symbols.lookup(fqName: companionInfo.fqName + [interner.intern("fromClosedRange")])
        )
        let fromClosedRangeSignature = try #require(sema.symbols.functionSignature(for: fromClosedRangeSymbol))

        #expect(sema.symbols.externalLinkName(for: fromClosedRangeSymbol) == "kk_char_progression_fromClosedRange")
        #expect(fromClosedRangeSignature.parameterTypes == [sema.types.charType, sema.types.charType, sema.types.intType])
        #expect(fromClosedRangeSignature.returnType == charProgressionType)

        let bundledToListName = ["kotlin", "ranges", "toList"].map { interner.intern($0) }
        let bundledToListSymbol = try #require(sema.symbols.lookupAll(fqName: bundledToListName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == charProgressionType
                && signature.parameterTypes.isEmpty
        })
        let bundledToListSignature = try #require(sema.symbols.functionSignature(for: bundledToListSymbol))
        #expect(sema.symbols.externalLinkName(for: bundledToListSymbol) == nil)
        #expect(
            sema.types.displayName(
                of: bundledToListSignature.returnType,
                symbols: sema.symbols,
                interner: interner
            ) == "List<Char>"
        )

        let bundledIsEmptyName = ["kotlin", "ranges", "isEmpty"].map { interner.intern($0) }
        let bundledIsEmptySymbol = try #require(sema.symbols.lookupAll(fqName: bundledIsEmptyName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == charProgressionType
                && signature.parameterTypes.isEmpty
        })
        #expect(sema.symbols.externalLinkName(for: bundledIsEmptySymbol) == nil)
        #expect(sema.symbols.symbol(bundledIsEmptySymbol)?.flags.contains(.synthetic) == false)
        #expect(
            functionExternalLink(
                for: "CharProgression",
                member: "isEmpty",
                parameterCount: 0,
                sema: sema,
                interner: interner
            ) == nil
        )
        #expect(
            functionExternalLink(
                for: "CharProgression",
                member: "step",
                parameterCount: 1,
                sema: sema,
                interner: interner
            ) == "kk_char_range_step"
        )

        // MARK: - Range random / firstOrNull / lastOrNull external links

        let randomExpected: [(owner: String, link: String)] = [
            ("IntRange", "kk_range_random"),
            ("LongRange", "kk_long_range_random"),
            ("CharRange", "kk_range_random"),
            ("UIntRange", "kk_uint_range_random"),
            ("ULongRange", "kk_ulong_range_random"),
        ]

        let firstOrNullExpected: [(owner: String, link: String)] = [
            ("IntRange", "kk_range_firstOrNull"),
            ("LongRange", "kk_long_range_firstOrNull"),
            ("ULongRange", "kk_ulong_range_firstOrNull"),
        ]

        let lastOrNullExpected: [(owner: String, link: String)] = [
            ("IntRange", "kk_range_lastOrNull"),
            ("LongRange", "kk_long_range_lastOrNull"),
            ("ULongRange", "kk_ulong_range_lastOrNull"),
        ]

        for expectation in firstOrNullExpected {
            #expect(
                externalLink(for: expectation.owner, member: "firstOrNull", sema: sema, interner: interner) == expectation.link,
                "\(expectation.owner).firstOrNull should link to \(expectation.link)"
            )
        }

        for expectation in lastOrNullExpected {
            #expect(
                externalLink(for: expectation.owner, member: "lastOrNull", sema: sema, interner: interner) == expectation.link,
                "\(expectation.owner).lastOrNull should link to \(expectation.link)"
            )
        }

        for expectation in randomExpected {
            #expect(
                externalLink(for: expectation.owner, member: "random", sema: sema, interner: interner) == expectation.link,
                "\(expectation.owner).random should link to \(expectation.link)"
            )
        }

        // MARK: - Call expression binding checks

        let probes: [(function: String, expectedLink: String, expectedType: TypeID)] = [
            ("intProbe", "kk_range_random", sema.types.intType),
            ("longProbe", "kk_long_range_random", sema.types.longType),
            ("charProbe", "kk_range_random", sema.types.charType),
            ("uintProbe", "kk_uint_range_random", sema.types.uintType),
            ("ulongProbe", "kk_ulong_range_random", sema.types.ulongType),
        ]

        for entry in probes {
            let function = try #require(
                functionDecl(named: entry.function, in: ast, interner: interner),
                "Missing function \(entry.function)"
            )
            let exprID = try #require(
                firstCallExpr(named: "random", in: function, ast: ast, interner: interner),
                "Missing range.random() call in \(entry.function)"
            )
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: exprID)?.chosenCallee,
                "No call binding for range.random() in \(entry.function)"
            )
            let link = try #require(
                sema.symbols.externalLinkName(for: chosenCallee),
                "No external link for range.random() in \(entry.function)"
            )
            #expect(link == entry.expectedLink, "\(entry.function) should resolve to \(entry.expectedLink), got \(link)")
            #expect(sema.bindings.exprTypes[exprID] == entry.expectedType, "Unexpected return type for \(entry.function)")
        }
    }
}
#endif
