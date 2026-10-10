import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    if let lock = try SingleInstanceLock.acquire(at: directory) {
        print("acquired")
        fflush(stdout)
        withExtendedLifetime(lock) { Thread.sleep(forTimeInterval: Double(CommandLine.arguments[2]) ?? 0) }
    } else {
        print("busy")
        exit(2)
    }
} catch { print(error); exit(3) }
