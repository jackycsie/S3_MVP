import Foundation

class AWSConfiguration: ObservableObject {
    @Published var accessKey: String {
        didSet {
            UserDefaults.standard.set(accessKey, forKey: "AWSAccessKey")
        }
    }
    
    @Published var secretKey: String {
        didSet {
            UserDefaults.standard.set(secretKey, forKey: "AWSSecretKey")
        }
    }
    
    @Published var region: String {
        didSet {
            UserDefaults.standard.set(region, forKey: "AWSRegion")
        }
    }
    
    @Published var isLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: "AWSIsLoggedIn")
        }
    }
    
    init() {
        self.accessKey = UserDefaults.standard.string(forKey: "AWSAccessKey") ?? ""
        self.secretKey = UserDefaults.standard.string(forKey: "AWSSecretKey") ?? ""
        self.region = UserDefaults.standard.string(forKey: "AWSRegion") ?? "美國東部 (us-east-1)"
        self.isLoggedIn = UserDefaults.standard.bool(forKey: "AWSIsLoggedIn")
    }
    
    func logout() {
        isLoggedIn = false
        // 可以選擇是否清除憑證
        // accessKey = ""
        // secretKey = ""
    }
} 