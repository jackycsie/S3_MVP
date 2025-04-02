import Foundation
import AWSS3
import AWSClientRuntime
import ClientRuntime
import AWSSDKIdentity

enum AWSCredentialError: LocalizedError {
    case invalidCredentials
    case networkError
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "憑證無效：請檢查您的 Access Key 和 Secret Key 是否正確"
        case .networkError:
            return "網絡錯誤：請檢查您的網絡連接"
        case .unknown:
            return "未知錯誤：請稍後重試"
        }
    }
}

class AWSCredentialUtility {
    static func validateCredentials(accessKey: String, secretKey: String, region: String) async throws -> Bool {
        let credentials = AWSCredentialIdentity(
            accessKey: accessKey,
            secret: secretKey
        )
        
        let provider = try StaticAWSCredentialIdentityResolver(credentials)
        
        do {
            let config = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: provider,
                region: region
            )
            
            let client = S3Client(config: config)
            
            // 嘗試列出存儲桶來驗證憑證
            _ = try await client.listBuckets(input: ListBucketsInput())
            return true
        } catch let error as AWSServiceError {
            print("AWS Service Error: \(error.message ?? "No message")")
            if let errorMessage = error.message {
                if errorMessage.contains("InvalidAccessKeyId") || errorMessage.contains("SignatureDoesNotMatch") {
                    throw AWSCredentialError.invalidCredentials
                } else if errorMessage.contains("Network") || errorMessage.contains("connect") {
                    throw AWSCredentialError.networkError
                }
            }
            throw AWSCredentialError.unknown
        } catch {
            print("Other Error: \(error.localizedDescription)")
            throw AWSCredentialError.unknown
        }
    }
} 