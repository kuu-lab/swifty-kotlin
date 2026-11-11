#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CompilerPluginParcelizeSerializationBodiesTests {
    @Test
    func parcelizeSynthesizesCreatorAndFieldWriteReadInKIR() throws {
        let androidStub = """
        package android.os

        interface Parcelable {
            interface Creator<T> {
                fun createFromParcel(parcel: Parcel): T
                fun newArray(size: Int): Array<T?>
            }
        }

        class Parcel {
            private val ints = mutableListOf<Int>()
            private val strings = mutableListOf<String>()
            private var intIdx = 0
            private var strIdx = 0

            fun writeInt(v: Int) { ints.add(v) }
            fun writeString(v: String) { strings.add(v) }
            fun readInt(): Int = ints[intIdx++]
            fun readString(): String = strings[strIdx++]
        }
        """

        let parcelizeStub = """
        package kotlinx.parcelize

        annotation class Parcelize
        annotation class IgnoredOnParcel
        """

        let userSource = """
        package com.example

        import android.os.Parcel
        import android.os.Parcelable
        import kotlinx.parcelize.IgnoredOnParcel
        import kotlinx.parcelize.Parcelize

        @Parcelize
        class Item(val name: String, val qty: Int) : Parcelable {
            @IgnoredOnParcel
            val cached: Int = 99
        }

        fun roundTrip(p: Parcel, item: Item): Item {
            item.writeToParcel(p, 0)
            val created: Item = Item.CREATOR.createFromParcel(p)
            val arr = Item.CREATOR.newArray(2)
            return created
        }
        """

        try withTemporaryFiles(contents: [androidStub, parcelizeStub, userSource]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let itemSym = try #require(sema.symbols.lookup(fqName: [
                interner.intern("com"), interner.intern("example"), interner.intern("Item"),
            ]))
            let info = try #require(sema.parcelizeClasses[itemSym])
            #expect(info.properties.count == 2)
            #expect(info.creatorObjectSymbol != nil)
            #expect(info.createFromParcelMethod != nil)
            #expect(info.newArrayMethod != nil)

            let module = try #require(ctx.kir)
            let createSym = try #require(info.createFromParcelMethod)
            let createFunc = try #require(module.arena.function(for: createSym))
            let hasObjectNew = createFunc.body.contains {
                if case let .call(_, callee, _, _, _, _, _, _) = $0 {
                    return interner.resolve(callee) == "kk_object_new"
                }
                return false
            }
            #expect(hasObjectNew)
        }
    }

    @Test
    func serializationSynthesizesKSerializerMembersAndRespectsSerialNameAndTransient() throws {
        let userSource = """
        package com.example

        import kotlinx.serialization.SerialName
        import kotlinx.serialization.Serializable
        import kotlinx.serialization.Transient

        @Serializable
        class Account(
            @SerialName("user_id")
            val id: Int,
            val label: String,
            @Transient
            val secret: String = "hidden"
        )

        fun inspectSerializer(): Int {
            val s = Account.serializer()
            return s.descriptor.elementsCount
        }
        """

        try withTemporaryFiles(contents: [userSource]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let accountSym = try #require(sema.symbols.lookup(fqName: [
                interner.intern("com"), interner.intern("example"), interner.intern("Account"),
            ]))
            let info = try #require(sema.serializationClasses[accountSym])
            #expect(info.serializableProperties.map(\.serialName) == ["user_id", "label"])
            #expect(info.descriptorGetter != nil)
            #expect(info.serializeMethod != nil)
            #expect(info.deserializeMethod != nil)

            let module = try #require(ctx.kir)
            let serializeSym = try #require(info.serializeMethod)
            let serializeFunc = try #require(module.arena.function(for: serializeSym))
            let callsBeginStructure = serializeFunc.body.contains {
                if case let .virtualCall(_, callee, _, _, _, _, _, _) = $0 {
                    return interner.resolve(callee) == "beginStructure"
                }
                return false
            }
            #expect(callsBeginStructure)
        }
    }
}
#endif
