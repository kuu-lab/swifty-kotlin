@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct PersistentListRemoveAllOverloadResolutionTests {
    private static let source = """
    package persistentlist

    interface PersistentCollection<out E> : Collection<E> {
        fun removeAll(elements: Collection<@UnsafeVariance E>): PersistentCollection<E>
        fun removeAll(predicate: (E) -> Boolean): PersistentCollection<E>
        fun retainAll(elements: Collection<@UnsafeVariance E>): PersistentCollection<E>
        fun retainAll(predicate: (E) -> Boolean): PersistentCollection<E>
    }

    interface PersistentList<out E> : PersistentCollection<E> {
        override fun removeAll(elements: Collection<@UnsafeVariance E>): PersistentList<E>
        override fun removeAll(predicate: (E) -> Boolean): PersistentList<E>
        override fun retainAll(elements: Collection<@UnsafeVariance E>): PersistentList<E>
        override fun retainAll(predicate: (E) -> Boolean): PersistentList<E>
    }

    abstract class AbstractPersistentList<E> : PersistentList<E> {
        fun removeAllWithTypedPredicate(predicate: (E) -> Boolean): PersistentList<E> = removeAll(predicate)
        fun retainAllWithTypedPredicate(predicate: (E) -> Boolean): PersistentList<E> = retainAll(predicate)

        override fun removeAll(elements: Collection<E>): PersistentList<E> {
            if (elements.isEmpty()) return this
            return removeAll { elements.contains(it) }
        }

        override fun retainAll(elements: Collection<E>): PersistentList<E> {
            if (elements.isEmpty()) return this
            return retainAll { !elements.contains(it) }
        }
    }

    fun implicitRemove(list: PersistentList<String>, elements: Collection<String>): PersistentList<String> =
        list.removeAll { elements.contains(it) }

    fun explicitRemove(list: PersistentList<String>, elements: Collection<String>): PersistentList<String> =
        list.removeAll { item: String -> elements.contains(item) }

    fun typedValueRemove(list: PersistentList<String>, predicate: (String) -> Boolean): PersistentList<String> =
        list.removeAll(predicate)

    fun collectionRemove(list: PersistentList<String>, elements: Collection<String>): PersistentList<String> =
        list.removeAll(elements)

    fun implicitRetain(list: PersistentList<String>, elements: Collection<String>): PersistentList<String> =
        list.retainAll { elements.contains(it) }

    fun typedValueRetain(list: PersistentList<String>, predicate: (String) -> Boolean): PersistentList<String> =
        list.retainAll(predicate)

    fun collectionRetain(list: PersistentList<String>, elements: Collection<String>): PersistentList<String> =
        list.retainAll(elements)
    """

    @Test(arguments: [false, true])
    func sameNameOverloadsSelectFunctionAndCollectionParameterShapes(usingStdlibKklib: Bool) throws {
        if usingStdlibKklib {
            TestStdlibCache.shared.prepare()
        }
        let ctx = makeContextFromSource(Self.source, allowDefaultStdlibLibrary: usingStdlibKklib)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map {
            "\($0.code): \($0.message) at \($0.primaryRange?.start.offset ?? -1)"
        }
        #expect(errors.isEmpty, "\(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        var functionOverloads = 0
        var collectionOverloads = 0
        var callCount = 0

        for (index, expr) in ast.arena.exprs.enumerated() {
            let id = ExprID(rawValue: Int32(index))
            guard ast.arena.exprRange(id)?.start.file == userFileID else { continue }
            let name: InternedString
            let arguments: [CallArgument]
            switch expr {
            case let .memberCall(_, memberName, _, callArguments, _):
                name = memberName
                arguments = callArguments
            case let .call(callee, _, callArguments, _):
                guard case let .nameRef(callName, _) = ast.arena.expr(callee) else { continue }
                name = callName
                arguments = callArguments
            default:
                continue
            }
            guard ["removeAll", "retainAll"].contains(ctx.interner.resolve(name)) else { continue }
            callCount += 1

            guard let binding = sema.bindings.callBinding(for: id) else {
                Issue.record("No resolved call for \(ctx.interner.resolve(name)) at \(ast.arena.exprRange(id)?.start.offset ?? -1)")
                continue
            }
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            let parameterType = try #require(signature.parameterTypes.first)
            let argument = try #require(arguments.first)
            let argumentType = try #require(sema.bindings.exprType(for: argument.expr))
            let parameterKind = sema.types.kind(of: sema.types.makeNonNullable(parameterType))
            let argumentKind = sema.types.kind(of: sema.types.makeNonNullable(argumentType))

            if case .functionType = parameterKind {
                functionOverloads += 1
                guard case let .functionType(functionType) = parameterKind else { continue }
                #expect(functionType.params.count == 1)
                #expect(functionType.returnType == sema.types.booleanType)
            } else {
                collectionOverloads += 1
                guard case let .classType(parameterClass) = parameterKind,
                      case .classType = argumentKind else {
                    Issue.record("Expected the collection overload for a Collection argument")
                    continue
                }
                #expect(sema.symbols.symbol(parameterClass.classSymbol)?.fqName.map(ctx.interner.resolve) == [
                    "kotlin", "collections", "Collection"
                ])
            }

            let resultType = try #require(sema.bindings.exprType(for: id))
            guard case let .classType(resultClass) = sema.types.kind(of: sema.types.makeNonNullable(resultType)) else {
                Issue.record("Expected a PersistentList result")
                continue
            }
            #expect(sema.symbols.symbol(resultClass.classSymbol)?.fqName.map(ctx.interner.resolve) == [
                "persistentlist", "PersistentList"
            ])
        }

        #expect(callCount == 11)
        #expect(functionOverloads == 9)
        #expect(collectionOverloads == 2)
    }
}
