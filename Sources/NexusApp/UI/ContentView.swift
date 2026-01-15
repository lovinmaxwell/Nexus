import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DownloadTask.createdDate, order: .reverse) private var tasks: [DownloadTask]
    
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(tasks) { task in
                    NavigationLink(destination: TaskDetailView(task: task)) {
                        VStack(alignment: .leading) {
                            Text(task.sourceURL.lastPathComponent)
                                .font(.headline)
                            Text(task.destinationPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select a download task")
        }
    }

    private func addItem() {
        withAnimation {
            // Stub: Add a dummy task for testing
            let newItem = DownloadTask(sourceURL: URL(string: "http://speedtest.tele2.net/1MB.zip")!, destinationPath: "/tmp/NexusTest_1MB.zip")
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(tasks[index])
            }
        }
    }
}

struct TaskDetailView: View {
    @Bindable var task: DownloadTask
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(task.id.uuidString)
                .font(.caption)
            
            LabeledContent("Status", value: "\(task.status)")
            LabeledContent("Size", value: "\(task.totalSize) bytes")
            LabeledContent("Destination", value: task.destinationPath)
            
            Button("Start Download") {
                let container = modelContext.container
                let coordinator = TaskCoordinator(taskID: task.id, container: container)
                Task {
                    await coordinator.start()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
        .navigationTitle(task.sourceURL.lastPathComponent)
    }
}

