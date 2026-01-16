import Foundation
import AppKit
import UserNotifications
import SwiftData

/// Executes post-process actions when queues complete.
///
/// Supports system sleep, shutdown, script execution, and notifications.
@MainActor
class PostProcessActionExecutor {
    static let shared = PostProcessActionExecutor()
    
    private init() {
        requestNotificationPermission()
    }
    
    /// Requests notification permission from the user.
    private func requestNotificationPermission() {
        // Check if we're in a test environment (no bundle)
        guard Bundle.main.bundleIdentifier != nil else {
            print("PostProcessActionExecutor: Skipping notification permission in test environment")
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("PostProcessActionExecutor: Failed to request notification permission - \(error)")
            } else if granted {
                print("PostProcessActionExecutor: Notification permission granted")
            }
        }
    }
    
    /// Executes the post-process action for a completed queue.
    ///
    /// - Parameters:
    ///   - queue: The queue that has completed
    ///   - context: The model context for saving state
    func executePostProcessAction(for queue: DownloadQueue, context: ModelContext) {
        guard queue.postProcessAction != .none else { return }
        guard !queue.postProcessExecuted else { return }  // Don't execute twice
        
        print("PostProcessActionExecutor: Executing action \(queue.postProcessAction) for queue '\(queue.name)'")
        
        switch queue.postProcessAction {
        case .none:
            break
            
        case .systemSleep:
            executeSystemSleep()
            
        case .systemShutdown:
            executeSystemShutdown()
            
        case .runScript:
            if let scriptPath = queue.postProcessScriptPath {
                executeScript(at: scriptPath)
            } else {
                print("PostProcessActionExecutor: Script path not set for queue '\(queue.name)'")
            }
            
        case .sendNotification:
            sendNotification(for: queue)
        }
        
        // Mark as executed
        queue.postProcessExecuted = true
        try? context.save()
    }
    
    /// Puts the system to sleep.
    private func executeSystemSleep() {
        print("PostProcessActionExecutor: Putting system to sleep...")
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["sleepnow"]
        do {
            try task.run()
        } catch {
            print("PostProcessActionExecutor: Failed to execute sleep command - \(error)")
        }
    }
    
    /// Shuts down the system.
    private func executeSystemShutdown() {
        print("PostProcessActionExecutor: Shutting down system...")
        let task = Process()
        task.launchPath = "/sbin/shutdown"
        task.arguments = ["-h", "now"]
        do {
            try task.run()
        } catch {
            print("PostProcessActionExecutor: Failed to execute shutdown command - \(error)")
        }
    }
    
    /// Executes a custom script at the specified path.
    ///
    /// - Parameter scriptPath: The file system path to the script
    private func executeScript(at scriptPath: String) {
        print("PostProcessActionExecutor: Executing script at \(scriptPath)")
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: scriptPath) else {
            print("PostProcessActionExecutor: Script file does not exist at \(scriptPath)")
            return
        }
        
        // Check if script is executable
        var isExecutable: ObjCBool = false
        guard fileManager.fileExists(atPath: scriptPath, isDirectory: &isExecutable) else {
            print("PostProcessActionExecutor: Cannot access script file")
            return
        }
        
        let task = Process()
        
        // Determine if it's a shell script or needs to be run with a specific interpreter
        if scriptPath.hasSuffix(".sh") || scriptPath.hasSuffix(".bash") {
            task.launchPath = "/bin/bash"
            task.arguments = [scriptPath]
        } else if scriptPath.hasSuffix(".py") {
            task.launchPath = "/usr/bin/python3"
            task.arguments = [scriptPath]
        } else if scriptPath.hasSuffix(".swift") {
            task.launchPath = "/usr/bin/swift"
            task.arguments = [scriptPath]
        } else {
            // Try to execute directly (must have shebang)
            task.launchPath = scriptPath
        }
        
        // Set up environment
        var environment = ProcessInfo.processInfo.environment
        environment["NEXUS_QUEUE_NAME"] = "queue"  // Could pass queue name if needed
        task.environment = environment
        
        do {
            try task.run()
            print("PostProcessActionExecutor: Script execution started")
        } catch {
            print("PostProcessActionExecutor: Failed to execute script - \(error)")
        }
    }
    
    /// Sends a notification when a queue completes.
    ///
    /// - Parameter queue: The completed queue
    private func sendNotification(for queue: DownloadQueue) {
        // Check if we're in a test environment (no bundle)
        guard Bundle.main.bundleIdentifier != nil else {
            print("PostProcessActionExecutor: Skipping notification in test environment for queue '\(queue.name)'")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Queue Complete"
        content.body = "All downloads in '\(queue.name)' have completed."
        content.sound = .default
        
        // Add completion info
        let completedCount = queue.completedTasksCount
        if completedCount > 0 {
            content.body += " (\(completedCount) file\(completedCount == 1 ? "" : "s"))"
        }
        
        let request = UNNotificationRequest(
            identifier: "queue-complete-\(queue.id.uuidString)",
            content: content,
            trigger: nil  // Immediate notification
        )
        
        let queueName = queue.name
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("PostProcessActionExecutor: Failed to send notification - \(error)")
            } else {
                print("PostProcessActionExecutor: Notification sent for queue '\(queueName)'")
            }
        }
    }
}
