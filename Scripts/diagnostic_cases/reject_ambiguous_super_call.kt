// EXPECT-REJECT
open class A2 { open fun f() = 1 }
interface I2 { fun f() = 2 }
class C3 : A2(), I2 { override fun f() = super.f() + 10 }
fun main() { println(C3().f()) }

interface Left { fun f() = 1 }
interface Right { fun f() = 2 }
class Both : Left, Right { override fun f() = super.f() }

open class Root { open fun f() = 1 }
open class Base : Root()
class Inherited : Base(), I2 { override fun f() = super.f() }

open class IntOverload { fun f(x: Int) = 1 }
interface StringOverload { fun f(x: String) = 2 }
class Overloaded : IntOverload(), StringOverload { fun g() = super.f(1) }

interface SharedLeft : Left
interface SharedRight : Left
class Diamond : SharedLeft, SharedRight { fun g() = super.f() }

interface AbstractLeft { fun f(): Int }
interface AbstractRight { fun f(): Int }
class Abstracts : AbstractLeft, AbstractRight { override fun f() = super.f() }
