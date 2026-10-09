import kotlinx.coroutines.test.*

fun main() {
    println(currentTime)
    println(testScheduler)
    println(backgroundScope)
}

@OptIn(ExperimentalCoroutinesApi::class)
fun qualifiedPropertiesRemainMembers(scope: TestScope) {
    println(scope.currentTime)
    println(scope.testScheduler)
    println(scope.backgroundScope)
    println(scope.testScheduler.currentTime)
}

@OptIn(ExperimentalCoroutinesApi::class)
fun implicitReceiverPropertiesRemainMembers(scope: TestScope) {
    with(scope) {
        println(currentTime)
        println(testScheduler)
        println(backgroundScope)
    }
}
