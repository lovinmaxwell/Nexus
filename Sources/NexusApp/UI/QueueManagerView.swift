import AppKit
import SwiftData
import SwiftUI

/// View for managing download queues.
struct QueueManagerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DownloadQueue.name) private var queues: [DownloadQueue]
    
    @State private var newQueueName = ""
    @State private var newQueueMaxConcurrent = 3
    @State private var showCreateQueue = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(queues) { queue in
                    QueueRowView(queue: queue)
                }
                .onDelete(perform: deleteQueues)
            }
            .navigationTitle("Queues")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateQueue = true
                    } label: {
                        Label("New Queue", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateQueue) {
                CreateQueueSheet(
                    queueName: $newQueueName,
                    maxConcurrent: $newQueueMaxConcurrent
                ) { name, maxConcurrent in
                    createQueue(name: name, maxConcurrent: maxConcurrent)
                }
            }
        }
        .frame(width: 500, height: 400)
    }
    
    private func createQueue(name: String, maxConcurrent: Int) {
        let queue = DownloadQueue(name: name, maxConcurrentDownloads: maxConcurrent)
        modelContext.insert(queue)
        try? modelContext.save()
        newQueueName = ""
        newQueueMaxConcurrent = 3
        showCreateQueue = false
    }
    
    private func deleteQueues(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(queues[index])
            }
            try? modelContext.save()
        }
    }
}

struct QueueRowView: View {
    @Bindable var queue: DownloadQueue
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [DownloadTask]
    
    var queueTasks: [DownloadTask] {
        allTasks.filter { $0.queue?.id == queue.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(queue.name)
                    .font(.headline)
                Spacer()
                if queue.isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Inactive", systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            HStack {
                Label("\(queue.maxConcurrentDownloads) concurrent", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Label("\(queueTasks.count) tasks", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if queue.isSynchronizationQueue {
                HStack {
                    Label("Sync Queue", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Checks every \(formatInterval(queue.checkInterval))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if queue.postProcessAction != .none {
                HStack {
                    Label("Post-process: \(postProcessActionName)", systemImage: "gearshape")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var postProcessActionName: String {
        switch queue.postProcessAction {
        case .none: return "None"
        case .systemSleep: return "Sleep"
        case .systemShutdown: return "Shutdown"
        case .runScript: return "Run Script"
        case .sendNotification: return "Notification"
        }
    }
    
    private func formatInterval(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }
}

struct CreateQueueSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var queueName: String
    @Binding var maxConcurrent: Int
    @State private var isSynchronizationQueue = false
    @State private var checkInterval: TimeInterval = 3600
    @State private var postProcessAction: PostProcessAction = .none
    @State private var scriptPath: String = ""
    
    let onCreate: (String, Int) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Create Queue")
                .font(.headline)
            
            TextField("Queue Name", text: $queueName)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("Max Concurrent:")
                    .frame(width: 120, alignment: .trailing)
                Stepper(value: $maxConcurrent, in: 1...32) {
                    Text("\(maxConcurrent)")
                        .frame(width: 40)
                }
                Spacer()
            }
            
            Toggle("Synchronization Queue", isOn: $isSynchronizationQueue)
            
            if isSynchronizationQueue {
                HStack {
                    Text("Check Interval:")
                        .frame(width: 120, alignment: .trailing)
                    Picker("Interval", selection: $checkInterval) {
                        Text("15 minutes").tag(900.0)
                        Text("30 minutes").tag(1800.0)
                        Text("1 hour").tag(3600.0)
                        Text("6 hours").tag(21600.0)
                        Text("12 hours").tag(43200.0)
                        Text("24 hours").tag(86400.0)
                    }
                    Spacer()
                }
            }
            
            HStack {
                Text("Post-Process:")
                    .frame(width: 120, alignment: .trailing)
                Picker("Action", selection: $postProcessAction) {
                    Text("None").tag(PostProcessAction.none)
                    Text("System Sleep").tag(PostProcessAction.systemSleep)
                    Text("System Shutdown").tag(PostProcessAction.systemShutdown)
                    Text("Run Script").tag(PostProcessAction.runScript)
                    Text("Send Notification").tag(PostProcessAction.sendNotification)
                }
                Spacer()
            }
            
            if postProcessAction == .runScript {
                HStack {
                    TextField("Script Path", text: $scriptPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        chooseScript()
                    }
                }
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Create") {
                    createQueue()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(queueName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func createQueue() {
        let queue = DownloadQueue(
            name: queueName,
            maxConcurrentDownloads: maxConcurrent,
            isSynchronizationQueue: isSynchronizationQueue,
            checkInterval: checkInterval,
            postProcessAction: postProcessAction
        )
        
        if postProcessAction == .runScript && !scriptPath.isEmpty {
            queue.postProcessScriptPath = scriptPath
        }
        
        // Insert and save will be handled by the parent view
        onCreate(queueName, maxConcurrent)
    }
    
    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.script, .shellScript, .executable]
        if panel.runModal() == .OK, let url = panel.url {
            scriptPath = url.path
        }
    }
}
