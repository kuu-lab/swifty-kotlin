import kotlin.native.RefinesInSwift
import kotlin.native.ShouldRefineInSwift

@RefinesInSwift
fun badFun() = 1

@RefinesInSwift
val badProp = 2

@RefinesInSwift
class BadFacade

@ShouldRefineInSwift
class BadClass

@RefinesInSwift
@Target(AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY)
annotation class RefinedForSwift

@RefinedForSwift
fun refinedViaMeta() = 3

@ShouldRefineInSwift
fun okFun() = 4

@ShouldRefineInSwift
val okProp = 5
