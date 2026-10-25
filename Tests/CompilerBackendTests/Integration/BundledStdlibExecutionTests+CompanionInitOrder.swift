import Testing

/// KUU-3225: JVM class-initialization order for companion objects. A
/// class's companion is its `<clinit>` content, so supertype companions —
/// the superclass chain first, then superinterfaces declaring concrete
/// members — initialize before the class's own companion. Covers
/// JetBrains testData `objects/companionObjectAccess/
/// companionObjectInitOrderWithSuperclass` and `...WithSuperinterface`
/// (KT-84267 / KT-40768).
extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func companionInitOrderWithSuperclass(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            var l = ""
            private fun log(t: String) {
                l += t + "\\n"
            }

            private fun logValue(t: String): String {
                log(t)
                return t
            }

            // companion-only access (no instance created)
            open class B1 {
                init { log("B1.init#1") }
                companion object { init { log("B1.Companion") } }
                init { log("B1.init#2") }
            }
            class A1 : B1() {
                init { log("A1.init#1") }
                companion object { init { log("A1.Companion") } }
                init { log("A1.init#2") }
            }

            // instance creation (triggers both companions then instance inits)
            open class B2 {
                init { log("B2.init#1") }
                companion object { init { log("B2.Companion") } }
                init { log("B2.init#2") }
            }
            class A2 : B2() {
                init { log("A2.init#1") }
                companion object { init { log("A2.Companion") } }
                init { log("A2.init#2") }
            }

            // companion access then instance creation
            open class B3 {
                init { log("B3.init#1") }
                companion object { init { log("B3.Companion") } }
                init { log("B3.init#2") }
            }
            class A3 : B3() {
                init { log("A3.init#1") }
                companion object { init { log("A3.Companion") } }
                init { log("A3.init#2") }
            }

            // instance creation then companion access
            open class B4 {
                init { log("B4.init#1") }
                companion object { init { log("B4.Companion") } }
                init { log("B4.init#2") }
            }
            class A4 : B4() {
                init { log("A4.init#1") }
                companion object { init { log("A4.Companion") } }
                init { log("A4.init#2") }
            }

            // 3-level hierarchy with companion access only
            open class C5 {
                companion object { init { log("C5.Companion") } }
            }
            open class B5 : C5() {
                companion object { init { log("B5.Companion") } }
            }
            class A5 : B5() {
                companion object { init { log("A5.Companion") } }
            }

            // 3-level hierarchy with instance creation
            open class C6 {
                init { log("C6.init") }
                companion object { init { log("C6.Companion") } }
            }
            open class B6 : C6() {
                init { log("B6.init") }
                companion object { init { log("B6.Companion") } }
            }
            class A6 : B6() {
                init { log("A6.init") }
                companion object { init { log("A6.Companion") } }
            }

            // intermediate class with no companion, companion access only
            open class C7 {
                companion object { init { log("C7.Companion") } }
            }
            open class B7 : C7()
            class A7 : B7() {
                companion object { init { log("A7.Companion") } }
            }

            // intermediate class with no companion; instance creation
            open class C8 {
                init { log("C8.init") }
                companion object { init { log("C8.Companion") } }
            }
            open class B8 : C8()
            class A8 : B8() {
                init { log("A8.init") }
                companion object { init { log("A8.Companion") } }
            }

            // parent companion access and repeated child companion access
            open class B9 {
                companion object { init { log("B9.Companion") } }
            }
            class A9 : B9() {
                companion object { init { log("A9.Companion") } }
            }

            // named private parent companion
            open class B10 {
                private companion object Parent { init { log("B10.Parent") } }
            }
            class A10 : B10() {
                companion object Child { init { log("A10.Child") } }
            }

            // child companion initializer reads from parent companion
            open class B11 {
                companion object {
                    val value = logValue("B11.Companion")
                }
            }
            class A11 : B11() {
                companion object {
                    val value = B11.value + "/" + logValue("A11.Companion")
                }
            }

            // superinterface companions are not superclass companions
            interface I12 {
                companion object { init { log("I12.Companion") } }
            }
            class A12 : I12 {
                companion object { init { log("A12.Companion") } }
            }

            // child companion object has its own superclass
            open class B13 {
                companion object { init { log("B13.Companion") } }
            }
            open class CompanionBase13 {
                init { log("CompanionBase13.init") }
            }
            class A13 : B13() {
                companion object : CompanionBase13() {
                    init { log("A13.Companion") }
                }
            }

            // two intermediate classes with no companion
            open class C14 {
                companion object { init { log("C14.Companion") } }
            }
            open class D14 : C14()
            open class B14 : D14()
            class A14 : B14() {
                companion object { init { log("A14.Companion") } }
            }

            // superclass and superinterface both have companions
            interface I15 {
                companion object {
                    val marker = logValue("I15.Companion")
                }
            }
            open class B15 {
                companion object { init { log("B15.Companion") } }
            }
            class A15 : B15(), I15 {
                companion object { init { log("A15.Companion") } }
            }

            // generic superclass
            open class B16<T> {
                companion object { init { log("B16.Companion") } }
            }
            class A16 : B16<String>() {
                companion object { init { log("A16.Companion") } }
            }

            fun box(): String {
                l = ""
                A1
                val r1 = l
                if (r1 != "B1.Companion\\nA1.Companion\\n") return "fail test1: '" + r1 + "'"

                l = ""
                A2()
                val r2 = l
                if (r2 != "B2.Companion\\nA2.Companion\\nB2.init#1\\nB2.init#2\\nA2.init#1\\nA2.init#2\\n") return "fail test2: '" + r2 + "'"

                l = ""
                A3
                log("--")
                A3()
                val r3 = l
                if (r3 != "B3.Companion\\nA3.Companion\\n--\\nB3.init#1\\nB3.init#2\\nA3.init#1\\nA3.init#2\\n") return "fail test3: '" + r3 + "'"

                l = ""
                A4()
                log("--")
                A4
                val r4 = l
                if (r4 != "B4.Companion\\nA4.Companion\\nB4.init#1\\nB4.init#2\\nA4.init#1\\nA4.init#2\\n--\\n") return "fail test4: '" + r4 + "'"

                l = ""
                A5
                val r5 = l
                if (r5 != "C5.Companion\\nB5.Companion\\nA5.Companion\\n") return "fail test5: '" + r5 + "'"

                l = ""
                A6()
                val r6 = l
                if (r6 != "C6.Companion\\nB6.Companion\\nA6.Companion\\nC6.init\\nB6.init\\nA6.init\\n") return "fail test6: '" + r6 + "'"

                l = ""
                A7
                val r7 = l
                if (r7 != "C7.Companion\\nA7.Companion\\n") return "fail test7: '" + r7 + "'"

                l = ""
                A8()
                val r8 = l
                if (r8 != "C8.Companion\\nA8.Companion\\nC8.init\\nA8.init\\n") return "fail test8: '" + r8 + "'"

                l = ""
                B9
                A9
                A9
                B9
                val r9 = l
                if (r9 != "B9.Companion\\nA9.Companion\\n") return "fail test9: '" + r9 + "'"

                l = ""
                A10
                val r10 = l
                if (r10 != "B10.Parent\\nA10.Child\\n") return "fail test10: '" + r10 + "'"

                l = ""
                if (A11.value != "B11.Companion/A11.Companion") return "fail test11 value: '" + A11.value + "'"
                val r11 = l
                if (r11 != "B11.Companion\\nA11.Companion\\n") return "fail test11: '" + r11 + "'"

                l = ""
                A12
                val r12 = l
                if (r12 != "A12.Companion\\n") return "fail test12: '" + r12 + "'"

                l = ""
                A13
                val r13 = l
                if (r13 != "B13.Companion\\nCompanionBase13.init\\nA13.Companion\\n") return "fail test13: '" + r13 + "'"

                l = ""
                A14
                val r14 = l
                if (r14 != "C14.Companion\\nA14.Companion\\n") return "fail test14: '" + r14 + "'"

                l = ""
                A15
                log("--")
                if (I15.marker != "I15.Companion") return "fail test15 marker"
                val r15 = l
                if (r15 != "B15.Companion\\nA15.Companion\\n--\\nI15.Companion\\n") return "fail test15: '" + r15 + "'"

                l = ""
                A16
                val r16 = l
                if (r16 != "B16.Companion\\nA16.Companion\\n") return "fail test16: '" + r16 + "'"

                return "OK"
            }

            fun main() {
                println(box())
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "CompanionInitOrderSuperclass",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func companionInitOrderWithSuperinterface(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            var l = ""
            private fun log(t: String) {
                l += t + "\\n"
            }

            // multiple interface inheritance
            interface I1 {
                fun i() {}
                companion object { init { log("I1.Companion") } }
            }
            interface J1 {
                fun j() {}
                companion object { init { log("J1.Companion") } }
            }
            interface K1 : I1 {
                fun k() {}
                companion object { init { log("K1.Companion") } }
            }
            interface L1 : J1 {
                fun l() {}
                companion object { init { log("L1.Companion") } }
            }
            interface M1 {
                companion object { init { log("M1.Companion") } }
            }
            open class B1 : J1, K1 {
                companion object { init { log("B1.Companion") } }
            }
            class A1: B1(), L1, M1 {
                companion object { init { log("A1.Companion") } }
            }

            // multiple interface inheritance; with instance creation
            interface I2 {
                fun i() {}
                companion object { init { log("I2.Companion") } }
            }
            interface J2 {
                fun j() {}
                companion object { init { log("J2.Companion") } }
            }
            interface K2 : I2 {
                fun k() {}
                companion object { init { log("K2.Companion") } }
            }
            interface L2 : J2 {
                fun l() {}
                companion object { init { log("L2.Companion") } }
            }
            interface M2 {
                companion object { init { log("M2.Companion") } }
            }
            open class B2 : J2, K2 {
                init { log("B2.init") }
                companion object { init { log("B2.Companion") } }
            }
            class A2: B2(), L2, M2 {
                init { log("A2.init") }
                companion object { init { log("A2.Companion") } }
            }

            // interface without non-abstract members extending one with
            // non-abstract members: J3 is skipped while I3 initializes
            interface I3 {
                fun foo() {}
                companion object { init { log("I3.Companion") } }
            }
            interface J3 : I3 {
                companion object { init { log("J3.Companion") } }
            }
            class A3 : J3 {
                companion object { init { log("A3.Companion") } }
            }

            // same as test3 but with explicit access to J4 after A4
            interface I4 {
                fun foo() {}
                companion object { init { log("I4.Companion") } }
            }
            interface J4 : I4 {
                companion object { init { log("J4.Companion") } }
            }
            class A4 : J4 {
                companion object { init { log("A4.Companion") } }
            }

            // implementing the same interface multiple times through the chain
            interface A5 {
                fun a() {}
                companion object { init { log("A5.Companion") } }
            }
            interface B5 : A5 {
                fun b() {}
                companion object { init { log("B5.Companion") } }
            }
            interface C5 : B5, A5 {
                fun c() {}
                companion object { init { log("C5.Companion") } }
            }
            class D5 : C5, A5 {
                companion object { init { log("D5.Companion") } }
            }

            interface I6 {
                val value: String get() = "I6"
                companion object { init { log("I6.Companion") } }
            }
            interface J6 : I6 {
                companion object { init { log("J6.Companion") } }
            }
            class A6 : J6 {
                companion object { init { log("A6.Companion") } }
            }

            // an interface with only abstract members is not an init dependency
            interface I7 {
                fun foo() {}
                companion object { init { log("I7.Companion") } }
            }
            interface J7 : I7 {
                fun bar()
                val value: Int
                companion object { init { log("J7.Companion") } }
            }
            class A7 : J7 {
                override fun bar() {}
                override val value: Int = 0
                companion object { init { log("A7.Companion") } }
            }

            fun box(): String {
                l = ""
                A1
                val r1 = l
                if (r1 != "J1.Companion\\nI1.Companion\\nK1.Companion\\nB1.Companion\\nL1.Companion\\nA1.Companion\\n") return "fail test1: '" + r1 + "'"

                l = ""
                A2()
                val r2 = l
                if (r2 != "J2.Companion\\nI2.Companion\\nK2.Companion\\nB2.Companion\\nL2.Companion\\nA2.Companion\\nB2.init\\nA2.init\\n") return "fail test2: '" + r2 + "'"

                l = ""
                A3
                val r3 = l
                if (r3 != "I3.Companion\\nA3.Companion\\n") return "fail test3: '" + r3 + "'"

                l = ""
                A4
                log("--")
                J4
                val r4 = l
                if (r4 != "I4.Companion\\nA4.Companion\\n--\\nJ4.Companion\\n") return "fail test4: '" + r4 + "'"

                l = ""
                D5
                val r5 = l
                if (r5 != "A5.Companion\\nB5.Companion\\nC5.Companion\\nD5.Companion\\n") return "fail test5: '" + r5 + "'"

                l = ""
                A6
                val r6 = l
                if (r6 != "I6.Companion\\nA6.Companion\\n") return "fail test6: '" + r6 + "'"

                l = ""
                A7
                val r7 = l
                if (r7 != "I7.Companion\\nA7.Companion\\n") return "fail test7: '" + r7 + "'"

                return "OK"
            }

            fun main() {
                println(box())
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "CompanionInitOrderSuperinterface",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
