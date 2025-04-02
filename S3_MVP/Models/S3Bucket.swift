import Foundation

struct S3Bucket: Identifiable, Hashable {
    let id = UUID()
    let name: String?
    
    static func == (lhs: S3Bucket, rhs: S3Bucket) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 