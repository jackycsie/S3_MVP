import SwiftUI
import AWSS3

struct ObjectListView: View {
    let bucket: String
    let prefix: String
    let objects: [S3Item]
    let isLoading: Bool
    
    var onCreateFolder: (String) -> Void
    var onUploadFile: () -> Void
    var onDeleteObject: (String) -> Void
    var onNavigate: (String) -> Void
    
    @State private var isShowingCreateDialog = false
    @State private var newItemName = ""
    
    var body: some View {
        List {
            ForEach(objects) { item in
                HStack {
                    Image(systemName: item.isFolder ? "folder" : "doc")
                    
                    if item.isFolder {
                        Button(action: { onNavigate(item.key) }) {
                            Text(item.key.replacingOccurrences(of: prefix, with: ""))
                        }
                    } else {
                        Text(item.key.replacingOccurrences(of: prefix, with: ""))
                    }
                    
                    Spacer()
                    
                    if !item.isFolder {
                        Text(item.formattedSize)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(item.formattedLastModified)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if objects.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No Items", systemImage: "doc")
                } description: {
                    Text("Upload files or create folders to get started")
                } actions: {
                    Button("Create Folder") {
                        isShowingCreateDialog = true
                    }
                    Button("Upload File") {
                        onUploadFile()
                    }
                }
            }
        }
        .alert("Create Folder", isPresented: $isShowingCreateDialog) {
            TextField("Folder Name", text: $newItemName)
            Button("Cancel", role: .cancel) {
                newItemName = ""
            }
            Button("Create") {
                onCreateFolder(newItemName)
                newItemName = ""
            }
            .disabled(newItemName.isEmpty)
        }
    }
}

#Preview {
    ObjectListView(
        bucket: "test-bucket",
        prefix: "",
        objects: [],
        isLoading: false,
        onCreateFolder: { _ in },
        onUploadFile: { },
        onDeleteObject: { _ in },
        onNavigate: { _ in }
    )
} 