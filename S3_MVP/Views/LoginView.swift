import SwiftUI
import AWSClientRuntime
import AWSS3
import ClientRuntime
import AWSSDKIdentity

struct LoginView: View {
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var region = "us-east-1"
    @Binding var isLoggedIn: Bool
    
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var connectionStatus: ConnectionStatus = .none
    
    private enum ConnectionStatus {
        case none
        case validating
        case success
        case failed(String)
        
        var color: Color {
            switch self {
            case .none:
                return .gray
            case .validating:
                return .orange
            case .success:
                return .green
            case .failed:
                return .red
            }
        }
        
        var icon: String {
            switch self {
            case .none:
                return "circle"
            case .validating:
                return "circle.dotted"
            case .success:
                return "checkmark.circle.fill"
            case .failed:
                return "exclamationmark.circle.fill"
            }
        }
        
        var message: String {
            switch self {
            case .none:
                return "尚未驗證連接"
            case .validating:
                return "正在驗證連接..."
            case .success:
                return "連接成功"
            case .failed(let error):
                return "連接失敗：\(error)"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("S3_MVP")
                .font(.title)
                .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Access Key")
                SecureField("", text: $accessKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Secret Key")
                SecureField("", text: $secretKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            Button("連接") {
                Task {
                    await connect()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
            
            Spacer()
        }
        .padding()
        .frame(width: 300)
    }
    
    private func validateIfReady() {
        guard !accessKey.isEmpty && !secretKey.isEmpty else {
            connectionStatus = .none
            return
        }
        
        Task {
            await validateConnection()
        }
    }
    
    private func validateConnection() async {
        guard !isValidating else { return }
        
        connectionStatus = .validating
        isValidating = true
        
        do {
            let isValid = try await AWSCredentialUtility.validateCredentials(
                accessKey: accessKey,
                secretKey: secretKey,
                region: region
            )
            
            if isValid {
                connectionStatus = .success
            }
        } catch let error as AWSCredentialError {
            connectionStatus = .failed(error.localizedDescription)
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
        
        isValidating = false
    }
    
    private func connect() async {
        do {
            // 创建凭证身份
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            // 创建静态凭证解析器
            let provider = try StaticAWSCredentialIdentityResolver(credentials)
            
            // 设置 S3 配置
            let config = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: provider,
                region: region
            )
            
            // 创建 S3 客户端并尝试列出存储桶以验证凭证
            let client = S3Client(config: config)
            _ = try await client.listBuckets(input: ListBucketsInput())
            
            // 保存凭证信息
            UserDefaults.standard.set(accessKey, forKey: "accessKey")
            UserDefaults.standard.set(secretKey, forKey: "secretKey")
            UserDefaults.standard.set(region, forKey: "region")
            
            isLoggedIn = true
        } catch {
            print("连接失败: \(error)")
            errorMessage = "连接失败：\(error.localizedDescription)"
        }
    }
    
    private var isConnectionSuccessful: Bool {
        if case .success = connectionStatus {
            return true
        }
        return false
    }
} 