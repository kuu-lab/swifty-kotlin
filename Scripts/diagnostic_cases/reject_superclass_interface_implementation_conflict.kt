// EXPECT-REJECT
open class SupFun { open fun who() = "C" }
interface IDFun { fun who(): String = "D" }
class ConflictFun : SupFun(), IDFun
open class SupProp { open val x = 1 }
interface IProp { val x: Int get() = 2 }
class ConflictProp : SupProp(), IProp
