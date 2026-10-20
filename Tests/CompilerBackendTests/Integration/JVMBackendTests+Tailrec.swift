#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func tailrecCallsBecomeLoopsWithDefaultsAndArgumentSnapshots(mode: EmitMode) throws {
        try assertJVM("""
        tailrec fun count(n: Int, sum: Long = 0L): Long =
            if (n == 0) sum else count(n - 1, sum + n)
        tailrec fun rotate(n: Int, a: Int, b: Int): Int {
            if (n == 0) return a * 10 + b
            return rotate(n - 1, b, a)
        }
        var defaults = 0
        fun observed(n: Int): Int { defaults++; return n }
        tailrec fun reset(n: Int, value: Int = observed(n)): Int =
            if (n == 0) value else reset(n - 1)
        tailrec fun Int.descend(): Int = if (this == 0) this else (this - 1).descend()
        open class Base { open fun count(n: Int): Int = n }
        class Final : Base() {
            final tailrec override fun count(n: Int): Int = if (n == 0) 0 else count(n - 1)
        }
        fun main() {
            println(count(100000))
            println(rotate(100001, 1, 2))
            println(reset(3))
            println(defaults)
            println(100000.descend())
            println(Final().count(100000))
        }
        """, "5000050000\n21\n0\n4\n0\n0\n", mode: mode)
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func tailrecLoopsAndOrdinaryMemberDefaultCalls(mode: EmitMode) throws {
        try assertJVM("""
        tailrec fun loop(n: Int): Int {
            while (n > 0) { return loop(n - 1) }
            return 0
        }
        tailrec fun doLoop(n: Int): Int {
            do { if (n > 0) return doLoop(n - 1) } while (false)
            return 0
        }
        tailrec fun forLoop(n: Int): Int {
            for (i in 0..0) { if (n > 0) return forLoop(n - 1) }
            return 0
        }
        open class BaseDefault { open fun f(n: Int, value: Int = 7): Int = value }
        class InheritedDefault : BaseDefault() {
            final tailrec override fun f(n: Int, value: Int): Int = if (n == 0) value else f(n - 1)
        }
        class ChangingReceiver(val value: Int) {
            tailrec fun f(n: Int, result: Int = value): Int =
                if (n == 0) result else ChangingReceiver(42).f(n - 1)
        }
        fun main() {
            println(loop(100000))
            println(doLoop(100000))
            println(forLoop(100000))
            println(InheritedDefault().f(2))
            println(ChangingReceiver(7).f(1))
        }
        """, "0\n0\n0\n7\n42\n", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func rejectsOverridableTailrecMembers(mode: EmitMode) throws {
        for source in [
            "open class A { open tailrec fun f(n:Int):Int = if(n==0) 0 else f(n-1) }; fun main() {}",
            "interface I { tailrec fun f(n:Int):Int = if(n==0) 0 else f(n-1) }; class C:I; fun main() {}",
            "open class A { open fun f(n:Int):Int=0 }; open class B:A(){ tailrec override fun f(n:Int):Int = if(n==0) 0 else f(n-1) }; fun main() {}",
        ] {
            try withWorkspace { root in
                let result = try compile(source, root: root, mode: mode)
                #expect(result.0 != 0)
                #expect(result.1.contains { $0.severity == .error && $0.message.contains("tailrec") })
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func tailrecExplicitReturnsInsideExpressionChildren(mode: EmitMode) throws {
        try assertJVM("""
        fun accept(n: Int): Int = n
        tailrec fun whileCondition(n:Int):Int {
            while(if(n>0) return whileCondition(n-1) else false) {}
            return 0
        }
        tailrec fun doCondition(n:Int):Int {
            do {} while(if(n>0) return doCondition(n-1) else false)
            return 0
        }
        tailrec fun forIterable(n:Int):Int {
            for(i in if(n>0) return forIterable(n-1) else intArrayOf()) {}
            return 0
        }
        tailrec fun ifCondition(n:Int):Int {
            if(if(n>0) return ifCondition(n-1) else true) return 0
            return 0
        }
        tailrec fun whenSubject(n:Int):Int {
            when(if(n>0) return whenSubject(n-1) else 0) { else -> return 0 }
        }
        tailrec fun whenCondition(n:Int):Int {
            when(n) { if(n>0) return whenCondition(n-1) else -1 -> return 0; else -> return 0 }
        }
        tailrec fun initializer(n:Int):Int {
            val value=if(n>0) return initializer(n-1) else 0
            return value
        }
        tailrec fun assignment(n:Int):Int {
            var value=0
            value=if(n>0) return assignment(n-1) else 0
            return value
        }
        tailrec fun argument(n:Int):Int {
            accept(if(n>0) return argument(n-1) else 0)
            return 0
        }
        tailrec fun template(n:Int):Int {
            val value="${if(n>0) return template(n-1) else 0}"
            return value.length - 1
        }
        fun main() {
            println(whileCondition(100000))
            println(doCondition(100000))
            println(forIterable(100000))
            println(ifCondition(100000))
            println(whenSubject(100000))
            println(whenCondition(100000))
            println(initializer(100000))
            println(assignment(100000))
            println(argument(100000))
            println(template(100000))
        }
        """, "0\n0\n0\n0\n0\n0\n0\n0\n0\n0\n", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func tailrecConstructorArgumentsAbandonUninitializedReceivers(mode: EmitMode) throws {
        try assertJVM("""
        var constructed = 0
        class Box(val value: Int) { init { constructed++ } }
        tailrec fun insideConstructor(n: Int): Int {
            if (n == 0) return 0
            val box = Box(Box(if (n > 0) return insideConstructor(n - 1) else 1).value)
            return box.value
        }
        fun main() {
            println(insideConstructor(100000))
            println(constructed)
            println(insideConstructor(-1))
            println(constructed)
        }
        """, "0\n0\n1\n2\n", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func tailrecKeepsLambdaFinallyAndNonTailCallsOrdinary(mode: EmitMode) throws {
        try assertJVM("""
        var finalizers = 0
        tailrec fun inFinally(n:Int):Int {
            if(n==0) return 0
            try { return inFinally(n-1) } finally { finalizers++ }
        }
        tailrec fun inLambda(n:Int):Int {
            val call:()->Int = { if(n==0) 0 else inLambda(n-1) }
            return call()+1
        }
        tailrec fun nonTail(n:Int):Int = if(n==0) 0 else nonTail(n-1)+1
        fun main(){println(inFinally(3));println(finalizers);println(inLambda(3));println(nonTail(3))}
        """, "0\n3\n4\n3\n", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func tailrecNullableExtensionSafeCallsPreserveNull(mode: EmitMode) throws {
        try assertJVM("""
        tailrec fun Int?.f(n:Int):Int?=if(n==0)this else this?.f(n-1); fun main(){println(7.f(100000));val x:Int?=null;println(x.f(1))}
        """, "7\nnull\n", mode: mode)
    }
}
#endif
