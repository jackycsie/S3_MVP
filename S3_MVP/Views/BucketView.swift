import SwiftUI
import AWSS3

struct BucketView: View {
    @Binding var accessKey: String
    @Binding var secretKey: String
    @Binding var region: String
    @Binding var currentBucket: String?
    @Binding var buckets: [S3Bucket]
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    
    var onBucketSelect: (String) -> Void
    var onRefresh: () async -> Void
    var onCreateBucket: (String) -> Void
    var onDeleteBucket: (String) -> Void
    
    @State private var isShowingCreateBucketDialog = false
    @State private var newBucketName = ""
    @State private var isCreatingBucket = false
    @State private var createBucketError: String?
    
    private var bucketSelection: Binding<String> {
        Binding<String>(
            get: { self.currentBucket ?? "" },
            set: { newValue in
                if !newValue.isEmpty {
                    self.onBucketSelect(newValue)
                }
            }
        )
    }
    
    var body: some View {
        List(selection: bucketSelection) {
            ForEach(buckets) { bucket in
                Text(bucket.name ?? "")
                    .tag(bucket.name ?? "")
            }
        }
        .overlay {
            if buckets.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No Buckets", systemImage: "bucket")
                } description: {
                    Text("Create a bucket to get started")
                } actions: {
                    Button("Create Bucket") {
                        isShowingCreateBucketDialog = true
                    }
                }
            }
        }
        .alert("Create Bucket", isPresented: $isShowingCreateBucketDialog) {
            TextField("Bucket Name", text: $newBucketName)
            Button("Cancel", role: .cancel) {
                newBucketName = ""
            }
            Button("Create") {
                onCreateBucket(newBucketName)
                newBucketName = ""
            }
            .disabled(newBucketName.isEmpty || isCreatingBucket)
        } message: {
            if let error = createBucketError {
                Text(error)
            }
        }
    }
}

#Preview {
    BucketView(
        accessKey: .constant(""),
        secretKey: .constant(""),
        region: .constant(""),
        currentBucket: .constant(nil),
        buckets: .constant([]),
        isLoading: .constant(false),
        errorMessage: .constant(nil),
        onBucketSelect: { _ in },
        onRefresh: { },
        onCreateBucket: { _ in },
        onDeleteBucket: { _ in }
    )
} 