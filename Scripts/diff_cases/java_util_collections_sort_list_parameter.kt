import java.util.Collections
import java.util.Comparator

class Job(val finish: Int)

fun sortJobs(jobs: List<Job>) {
    Collections.sort(jobs, Comparator.comparingInt { x: Job -> x.finish })
}

fun sortMutableJobs(jobs: MutableList<Job>) {
    Collections.sort(jobs, Comparator.comparingInt { x: Job -> x.finish })
}

fun sortNumbers(numbers: List<Int>) {
    Collections.sort(numbers)
}

fun main() {
    val jobs = arrayListOf(Job(4), Job(1), Job(3))
    sortJobs(jobs)
    println("list:${jobs.joinToString(",") { it.finish.toString() }}")

    val mutableJobs = arrayListOf(Job(5), Job(2), Job(4))
    sortMutableJobs(mutableJobs)
    println("mutable-list:${mutableJobs.joinToString(",") { it.finish.toString() }}")

    val numbers = arrayListOf(3, 1, 2)
    sortNumbers(numbers)
    println("natural-list:${numbers.joinToString()}")

    val readOnlyJobs: List<Job> = Collections.unmodifiableList(arrayListOf(Job(3), Job(1), Job(2)))
    try {
        sortJobs(readOnlyJobs)
        println("readonly:sorted")
    } catch (_: UnsupportedOperationException) {
        println("readonly:unsupported")
    }
}
