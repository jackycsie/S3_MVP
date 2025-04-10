import SwiftUI
import AWSS3
import AWSClientRuntime
import AWSSDKIdentity
import ClientRuntime
import UniformTypeIdentifiers
import AppKit

struct SyncConfig: Codable, Identifiable {
    var id = UUID()
    var localFolderPath: String
    var bucketName: String
    var prefix: String
    var syncTime: Date
    var isEnabled: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case id, localFolderPath, bucketName, prefix, syncTime, isEnabled
    }
    
    init(localFolderPath: String, bucketName: String, prefix: String, syncTime: Date, isEnabled: Bool = true) {
        self.localFolderPath = localFolderPath
        self.bucketName = bucketName
        self.prefix = prefix
        self.syncTime = syncTime
        self.isEnabled = isEnabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        localFolderPath = try container.decode(String.self, forKey: .localFolderPath)
        bucketName = try container.decode(String.self, forKey: .bucketName)
        prefix = try container.decode(String.self, forKey: .prefix)
        syncTime = try container.decode(Date.self, forKey: .syncTime)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(localFolderPath, forKey: .localFolderPath)
        try container.encode(bucketName, forKey: .bucketName)
        try container.encode(prefix, forKey: .prefix)
        try container.encode(syncTime, forKey: .syncTime)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

// 添加一個同步歷史記錄結構
struct SyncHistory: Codable, Identifiable {
    var id = UUID()
    var timestamp: Date
    var configId: UUID
    var localPath: String
    var targetBucket: String
    var prefix: String
    var status: String
    var details: [String]
    var success: Bool
    
    static func createSuccess(config: SyncConfig, details: [String]) -> SyncHistory {
        return SyncHistory(
            timestamp: Date(),
            configId: config.id,
            localPath: config.localFolderPath,
            targetBucket: config.bucketName,
            prefix: config.prefix,
            status: "成功",
            details: details,
            success: true
        )
    }
    
    static func createFailure(config: SyncConfig, error: String, details: [String]) -> SyncHistory {
        return SyncHistory(
            timestamp: Date(),
            configId: config.id,
            localPath: config.localFolderPath,
            targetBucket: config.bucketName,
            prefix: config.prefix,
            status: "失敗: \(error)",
            details: details,
            success: false
        )
    }
}

// 添加一個輔助視圖組件用於顯示同步日誌項目
struct SyncLogItem: View {
    let logText: String
    
    var body: some View {
        let textColor: Color = {
            if logText.contains("失敗") {
                return .red
            } else if logText.contains("成功") {
                return .green
            } else {
                return .primary
            }
        }()
        
        return Text(logText)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(textColor)
    }
}

// 添加一個輔助視圖來顯示狀態文本
struct StatusTextView: View {
    let status: String
    let isCaption: Bool
    
    var body: some View {
        let isError = status.contains("失敗")
        let textColor = isError ? Color.red : Color.green
        
        Text(status)
            .font(isCaption ? .caption : .body)
            .foregroundColor(textColor)
            .padding(.top, isCaption ? 4 : 0)
    }
}

// 添加一個視圖組件用於顯示同步歷史項目
struct SyncHistoryItemView: View {
    let history: SyncHistory
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                let folderName = history.localPath.split(separator: "/").last ?? ""
                Text(String(folderName))
                    .font(.headline)
                
                Text("\(history.targetBucket)/\(history.prefix)")
                    .font(.caption)
                
                Text(history.timestamp, formatter: createDateTimeFormatter())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            // 顯示成功或失敗圖標
            if history.success {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    // 創建日期時間格式化器
    private func createDateTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}

// 添加一個獨立的 View 用於顯示同步配置行
struct SyncConfigRowView: View {
    let config: SyncConfig
    let viewModel: SyncViewModel
    @Binding var configToDelete: SyncConfig?
    @Binding var showDeleteConfirmation: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(config.localFolderPath)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("同步到: \(config.bucketName)/\(config.prefix)")
                        .font(.subheadline)
                    Text("同步時間: \(config.syncTime, formatter: timeFormatter)")
                        .font(.caption)
                }
                Spacer()
                
                VStack {
                    Toggle("", isOn: Binding(
                        get: { config.isEnabled },
                        set: { _ in viewModel.toggleConfig(config) }
                    ))
                    .labelsHidden()
                    
                    Button(action: {
                        Task {
                            await viewModel.manualSync(config: config)
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isLoading)
                }
                
                Button(action: {
                    configToDelete = config
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading)
            }
            
            if !viewModel.syncStatus.isEmpty && viewModel.syncStatus.contains(config.localFolderPath) {
                StatusTextView(status: viewModel.syncStatus, isCaption: true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                configToDelete = config
                showDeleteConfirmation = true
            }) {
                Label("刪除", systemImage: "trash")
            }
            
            Button(action: {
                Task {
                    await viewModel.manualSync(config: config)
                }
            }) {
                Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
            }
            
            Button(action: {
                viewModel.toggleConfig(config)
            }) {
                Label(config.isEnabled ? "停用" : "啟用", systemImage: config.isEnabled ? "pause" : "play")
            }
        }
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateFormat = "HH:mm"  // 24 小時制
        return formatter
    }
}

// 添加一個視圖組件用於顯示創建新同步任務的部分
struct CreateSyncTaskView: View {
    @ObservedObject var viewModel: SyncViewModel
    
    var body: some View {
        Section("創建新同步任務") {
            HStack {
                Text("本地資料夾:")
                Spacer()
                Button(viewModel.newConfig.localFolderPath.isEmpty ? "選擇資料夾" : viewModel.newConfig.localFolderPath) {
                    viewModel.selectFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .foregroundColor(.white)
            }
            
            HStack {
                Text("目標 Bucket:")
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .controlSize(.small)
                } else {
                    Picker("選擇 Bucket", selection: $viewModel.selectedBucket) {
                        Text("請選擇").tag("")
                        ForEach(viewModel.availableBuckets, id: \.self) { bucket in
                            Text(bucket).tag(bucket)
                        }
                    }
                }
            }
            
            TextField("前綴路徑 (可選)", text: $viewModel.newConfig.prefix)
                .textFieldStyle(.roundedBorder)
            
            DatePicker("同步時間", selection: $viewModel.newConfig.syncTime, displayedComponents: .hourAndMinute)
            
            Button(action: {
                viewModel.saveConfig()
            }) {
                Text("保存設置")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.newConfig.localFolderPath.isEmpty || viewModel.selectedBucket.isEmpty || viewModel.isLoading)
            .padding(.top, 8)
        }
    }
}

// 添加一個視圖組件用於顯示說明信息
struct SyncHelpSectionView: View {
    var body: some View {
        Section("說明") {
            Text("• 選擇您想要同步的本地資料夾和目標 S3 Bucket")
            Text("• 可以設置一個前綴路徑，對應 S3 Bucket 內的目錄")
            Text("• 設置同步時間後，系統會在每天這個時間點進行同步")
            Text("• 您可以通過點擊同步按鈕立即執行同步")
            Text("• 切換開關可啟用或停用同步任務")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}

// 添加一個視圖組件用於顯示同步歷史詳情
struct SyncHistoryDetailView: View {
    let history: SyncHistory
    let onClose: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section("同步資訊") {
                    LabeledContent("本地資料夾") {
                        Text(history.localPath)
                    }
                    LabeledContent("目標存儲桶") {
                        Text(history.targetBucket)
                    }
                    LabeledContent("前綴路徑") {
                        Text(history.prefix)
                    }
                    LabeledContent("同步時間") {
                        Text(history.timestamp, formatter: createDateTimeFormatter())
                    }
                    LabeledContent("狀態") {
                        Text(history.status)
                            .foregroundColor(history.success ? .green : .red)
                    }
                }
                
                Section("詳細日誌") {
                    ForEach(history.details.indices, id: \.self) { index in
                        SyncLogItem(logText: history.details[index])
                    }
                }
            }
            .navigationTitle("同步詳情")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("關閉") {
                        onClose()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    // 創建日期時間格式化器
    private func createDateTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}

@MainActor
class SyncViewModel: ObservableObject {
    // 單例模式
    static let shared = SyncViewModel(accessKey: "", secretKey: "", region: "")
    
    @Published var configs: [SyncConfig] = []
    @Published var newConfig = SyncConfig(localFolderPath: "", bucketName: "", prefix: "", syncTime: Date())
    @Published var selectedBucket: String = ""
    @Published var availableBuckets: [String] = []
    @Published var syncStatus: String = ""
    @Published var isLoading = false
    @Published var lastSyncDate: Date? = nil
    @Published var isBackgroundSyncEnabled = true
    @Published var syncHistory: [SyncHistory] = []
    private let maxHistoryItems = 5
    
    // 計時器是靜態的，這樣可以在整個應用生命週期內存在
    private static var syncTimer: Timer? = nil
    
    #if os(iOS)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    var accessKey: String
    var secretKey: String
    var region: String
    
    init(accessKey: String, secretKey: String, region: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        
        log("初始化 SyncViewModel")
        
        // 嘗試從 UserDefaults 載入配置
        loadConfigsFromUserDefaults()
        
        // 如果沒有保存的配置，使用示例配置
        if self.configs.isEmpty {
            // 創建固定的示例配置
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let documentsDir = "\(homeDir)/Documents"
            
            let exampleConfig = SyncConfig(
                localFolderPath: documentsDir,
                bucketName: "示例目標桶",
                prefix: "example-folder/",
                syncTime: Date(),
                isEnabled: false
            )
            
            self.configs = [exampleConfig]
        }
        
        // 載入上次同步時間
        if let lastSyncTimeString = UserDefaults.standard.string(forKey: "LastSyncTime"),
           let lastSyncTime = ISO8601DateFormatter().date(from: lastSyncTimeString) {
            self.lastSyncDate = lastSyncTime
        }
        
        // 載入同步歷史記錄
        loadSyncHistory()
        
        // 更新認證信息
        updateCredentials(accessKey: accessKey, secretKey: secretKey, region: region)
        
        // 啟動同步計時器 (如果尚未啟動)
        Self.startGlobalSyncTimer(viewModel: self)
    }
    
    // 更新憑證信息
    func updateCredentials(accessKey: String, secretKey: String, region: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        log("更新認證信息: 區域 = \(region)")
    }
    
    // 全局靜態計時器控制
    static func startGlobalSyncTimer(viewModel: SyncViewModel) {
        // 如果計時器已存在，不重新創建
        if syncTimer != nil {
            viewModel.log("全局定時器已經在運行中")
            return
        }
        
        viewModel.log("啟動全局同步計時器")
        
        // 每分鐘檢查一次是否需要同步
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            viewModel.log("全局計時器觸發檢查...")
            Task {
                await viewModel.checkScheduledSync()
            }
        }
        
        // 確保計時器不會被RunLoop回收
        RunLoop.current.add(syncTimer!, forMode: .common)
        
        // 立即執行一次檢查
        Task {
            viewModel.log("初始全局檢查同步任務...")
            await viewModel.checkScheduledSync()
        }
        
        viewModel.log("全局同步計時器已啟動，間隔: 60秒")
    }
    
    // 原來的實例方法現在委託給靜態方法
    func startSyncTimer() {
        log("請求啟動同步計時器 (委託給全局計時器)")
        Self.startGlobalSyncTimer(viewModel: self)
    }
    
    // 停止定時同步計時器
    func stopSyncTimer() {
        print("停止同步計時器 (現在為全局管理，不會真正停止)")
        // 不再停止計時器，因為它是全局的
        // 僅記錄日誌以追蹤調用
    }
    
    // 檢查是否有需要執行的計劃同步
    func checkScheduledSync() async {
        log("檢查計劃同步任務...")
        
        guard isBackgroundSyncEnabled else {
            log("自動同步已停用，跳過檢查")
            return
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // 當前時間的小時和分鐘
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        
        // 使用 24 小時制顯示時間
        let formattedCurrentTime = String(format: "%02d:%02d", currentHour, currentMinute)
        log("當前時間: \(formattedCurrentTime)")
        
        // 記錄所有啟用的配置及其同步時間
        for config in configs where config.isEnabled {
            let syncHour = calendar.component(.hour, from: config.syncTime)
            let syncMinute = calendar.component(.minute, from: config.syncTime)
            
            // 使用 24 小時制顯示時間
            let formattedSyncTime = String(format: "%02d:%02d", syncHour, syncMinute)
            log("檢查配置: \(config.localFolderPath) -> \(config.bucketName)/\(config.prefix), 同步時間: \(formattedSyncTime)")
            
            // 檢查是否到達同步時間（允許 5 分鐘誤差）
            if currentHour == syncHour && abs(currentMinute - syncMinute) <= 5 {
                log("✓ 觸發同步: \(config.localFolderPath)")
                
                // 開始後台任務（如果在iOS上）
                startBackgroundTask()
                
                // 執行同步
                await syncFolder(config: config)
                
                // 更新最後同步時間
                updateLastSyncTime()
                
                // 結束後台任務
                endBackgroundTask()
            } else {
                log("✗ 時間不匹配，跳過同步: \(formattedSyncTime) vs 當前 \(formattedCurrentTime)")
            }
        }
        
        // 如果沒有啟用的配置，記錄該情況
        if !configs.contains(where: { $0.isEnabled }) {
            log("沒有啟用的同步配置")
        }
    }
    
    // 開始後台任務（在iOS上）
    func startBackgroundTask() {
        #if os(iOS)
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        #endif
    }
    
    // 結束後台任務
    func endBackgroundTask() {
        #if os(iOS)
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        #endif
    }
    
    // 更新最後同步時間
    func updateLastSyncTime() {
        let now = Date()
        lastSyncDate = now
        let dateString = ISO8601DateFormatter().string(from: now)
        UserDefaults.standard.set(dateString, forKey: "LastSyncTime")
    }
    
    // 執行手動同步並更新UI
    func manualSync(config: SyncConfig) async {
        // 開始後台任務
        startBackgroundTask()
        
        // 執行同步
        await syncFolder(config: config)
        
        // 更新最後同步時間
        updateLastSyncTime()
        
        // 結束後台任務
        endBackgroundTask()
    }
    
    // 保存配置到 UserDefaults
    func saveConfigsToUserDefaults() {
        print("正在保存配置到 UserDefaults")
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(configs) {
            UserDefaults.standard.set(encodedData, forKey: "SyncConfigs")
            print("成功保存 \(configs.count) 個同步配置")
        } else {
            print("保存配置失敗")
        }
    }
    
    // 從 UserDefaults 載入配置
    func loadConfigsFromUserDefaults() {
        print("正在從 UserDefaults 載入配置")
        guard let savedData = UserDefaults.standard.data(forKey: "SyncConfigs") else {
            print("UserDefaults 中沒有保存的配置")
            return
        }
        
        let decoder = JSONDecoder()
        do {
            let savedConfigs = try decoder.decode([SyncConfig].self, from: savedData)
            print("成功載入 \(savedConfigs.count) 個同步配置")
            
            // 驗證載入的配置
            var validConfigs: [SyncConfig] = []
            for config in savedConfigs {
                if !config.localFolderPath.isEmpty && !config.bucketName.isEmpty {
                    validConfigs.append(config)
                } else {
                    print("跳過無效配置: \(config)")
                }
            }
            
            self.configs = validConfigs
            print("有效配置數量: \(validConfigs.count)")
        } catch {
            print("解碼配置失敗: \(error.localizedDescription)")
        }
    }
    
    func saveConfig() {
        if !newConfig.localFolderPath.isEmpty && !selectedBucket.isEmpty {
            newConfig.bucketName = selectedBucket
            configs.append(newConfig)
            saveConfigsToUserDefaults()  // 保存到 UserDefaults
            
            newConfig = SyncConfig(localFolderPath: "", bucketName: "", prefix: "", syncTime: Date())
            selectedBucket = ""
        }
    }
    
    func loadBuckets() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            let config = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            let client = S3Client(config: config)
            let input = ListBucketsInput()
            let response = try await client.listBuckets(input: input)
            
            if let buckets = response.buckets {
                self.availableBuckets = buckets.map { $0.name ?? "" }
                    .filter { !$0.isEmpty }
            }
        } catch {
            print("加載 bucket 時出錯: \(error.localizedDescription)")
        }
    }
    
    // 保存同步歷史記錄
    func saveSyncHistory() {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(syncHistory) {
            UserDefaults.standard.set(encodedData, forKey: "SyncHistory")
            log("已保存 \(syncHistory.count) 條同步歷史記錄")
        }
    }
    
    // 載入同步歷史記錄
    func loadSyncHistory() {
        if let savedData = UserDefaults.standard.data(forKey: "SyncHistory"),
           let decodedHistory = try? JSONDecoder().decode([SyncHistory].self, from: savedData) {
            self.syncHistory = decodedHistory
            log("已載入 \(decodedHistory.count) 條同步歷史記錄")
        }
    }
    
    // 添加同步歷史記錄
    func addSyncHistory(_ history: SyncHistory) {
        // 將新記錄添加到列表開頭
        syncHistory.insert(history, at: 0)
        
        // 如果超過最大記錄數，移除最舊的記錄
        if syncHistory.count > maxHistoryItems {
            syncHistory = Array(syncHistory.prefix(maxHistoryItems))
        }
        
        // 保存歷史記錄
        saveSyncHistory()
    }
    
    // 修改同步文件夾方法以記錄每個文件的同步結果
    func syncFolder(config: SyncConfig) async {
        log("開始同步文件夾: \(config.localFolderPath) -> \(config.bucketName)/\(config.prefix)")
        
        var syncDetails: [String] = []
        syncDetails.append("開始同步：\(Date().formatted(date: .abbreviated, time: .standard))")
        
        do {
            syncStatus = "正在同步: \(config.localFolderPath) 到 \(config.bucketName)/\(config.prefix)"
            
            let credentials = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            
            let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
            
            let s3Config = try await S3Client.S3ClientConfiguration(
                awsCredentialIdentityResolver: identityResolver,
                region: region
            )
            
            let client = S3Client(config: s3Config)
            
            // 獲取本地文件列表
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(atPath: config.localFolderPath)
            
            log("找到 \(files.count) 個文件待同步")
            syncDetails.append("找到 \(files.count) 個文件待同步")
            
            var successCount = 0
            var failureCount = 0
            
            for file in files {
                let localPath = "\(config.localFolderPath)/\(file)"
                var isDir: ObjCBool = false
                
                if fileManager.fileExists(atPath: localPath, isDirectory: &isDir) && !isDir.boolValue {
                    log("同步文件: \(file)")
                    
                    do {
                        let fileURL = URL(fileURLWithPath: localPath)
                        let fileData = try Data(contentsOf: fileURL)
                        
                        let key = config.prefix.isEmpty ? file : "\(config.prefix)/\(file)"
                        
                        let input = PutObjectInput(
                            body: .data(fileData),
                            bucket: config.bucketName,
                            key: key
                        )
                        
                        _ = try await client.putObject(input: input)
                        syncStatus = "已上傳: \(file)"
                        log("文件上傳成功: \(file)")
                        syncDetails.append("✓ 上傳成功: \(file) (\(ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file)))")
                        successCount += 1
                    } catch {
                        log("文件上傳失敗: \(file) - \(error.localizedDescription)")
                        syncDetails.append("✗ 上傳失敗: \(file) - \(error.localizedDescription)")
                        failureCount += 1
                    }
                }
            }
            
            let summaryText = "同步完成：成功 \(successCount) 個文件，失敗 \(failureCount) 個文件"
            syncStatus = summaryText
            syncDetails.append(summaryText)
            log("同步任務完成: \(config.localFolderPath) - \(summaryText)")
            
            // 添加成功的同步歷史記錄
            addSyncHistory(SyncHistory.createSuccess(config: config, details: syncDetails))
        } catch {
            let errorMessage = "同步失敗: \(error.localizedDescription)"
            syncStatus = errorMessage
            syncDetails.append(errorMessage)
            log(errorMessage)
            
            // 添加失敗的同步歷史記錄
            addSyncHistory(SyncHistory.createFailure(config: config, error: error.localizedDescription, details: syncDetails))
        }
    }
    
    func toggleConfig(_ config: SyncConfig) {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index].isEnabled.toggle()
            saveConfigsToUserDefaults()  // 保存到 UserDefaults
        }
    }
    
    func removeConfig(_ config: SyncConfig) {
        log("正在刪除同步配置: \(config.localFolderPath) -> \(config.bucketName)/\(config.prefix)")
        configs.removeAll { $0.id == config.id }
        saveConfigsToUserDefaults()  // 儲存更改到 UserDefaults
    }
    
    func selectFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.message = "請選擇要同步的資料夾"
        openPanel.prompt = "選擇"
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                newConfig.localFolderPath = url.path
            }
        }
    }
    
    // 增加日誌記錄功能
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] SYNC_LOG: \(message)")
        
        // 將日誌保存到文件
        appendLogToFile(message: "[\(timestamp)] \(message)")
    }
    
    // 保存日誌到文件
    func appendLogToFile(message: String) {
        let fileManager = FileManager.default
        let logDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/S3_MVP")
        let logFile = logDirectory.appendingPathComponent("sync.log")
        
        // 創建日誌目錄（如果不存在）
        if !fileManager.fileExists(atPath: logDirectory.path) {
            do {
                try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            } catch {
                print("無法創建日誌目錄: \(error)")
                return
            }
        }
        
        // 添加日誌到文件
        do {
            let logMessage = message + "\n"
            if fileManager.fileExists(atPath: logFile.path) {
                let fileHandle = try FileHandle(forWritingTo: logFile)
                fileHandle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                try logMessage.data(using: .utf8)?.write(to: logFile)
            }
        } catch {
            print("寫入日誌失敗: \(error)")
        }
    }
}

struct SyncView: View {
    @ObservedObject var viewModel: SyncViewModel
    @SwiftUI.Environment(\.dismiss) var dismiss: DismissAction
    @State private var showDeleteConfirmation = false
    @State private var configToDelete: SyncConfig? = nil
    @State private var showHistoryDetails = false
    @State private var selectedHistory: SyncHistory? = nil
    
    var body: some View {
        NavigationStack {
            List {
                Section("現有同步任務") {
                    if viewModel.configs.isEmpty {
                        Text("無同步任務")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.configs) { config in
                            SyncConfigRowView(
                                config: config,
                                viewModel: viewModel,
                                configToDelete: $configToDelete,
                                showDeleteConfirmation: $showDeleteConfirmation
                            )
                        }
                    }
                }
                
                if let lastSync = viewModel.lastSyncDate {
                    Section("同步狀態") {
                        HStack {
                            Text("上次同步時間:")
                            Spacer()
                            Text(lastSync, formatter: dateTimeFormatter)
                                .foregroundColor(.secondary)
                        }
                        
                        Toggle("啟用自動同步", isOn: $viewModel.isBackgroundSyncEnabled)
                    }
                }
                
                if !viewModel.syncHistory.isEmpty {
                    Section("同步歷史") {
                        ForEach(viewModel.syncHistory) { history in
                            SyncHistoryItemView(history: history) {
                                selectedHistory = history
                                showHistoryDetails = true
                            }
                        }
                    }
                }
                
                // 使用新的組件替代原有的複雜部分
                CreateSyncTaskView(viewModel: viewModel)
                
                if !viewModel.syncStatus.isEmpty && !viewModel.syncStatus.contains("/") {
                    Section("同步狀態") {
                        StatusTextView(status: viewModel.syncStatus, isCaption: false)
                    }
                }
                
                // 使用新的幫助部分組件
                SyncHelpSectionView()
            }
            .navigationTitle("資料夾同步")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        viewModel.saveConfigsToUserDefaults()  // 在按下完成時保存配置
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("刷新") {
                        Task {
                            await viewModel.loadBuckets()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadBuckets()
                }
            }
            .onDisappear {
                viewModel.saveConfigsToUserDefaults()  // 在視圖消失時保存配置
                // 確保定時器仍在運行
                viewModel.startSyncTimer()
            }
            .alert("刪除同步任務", isPresented: $showDeleteConfirmation, presenting: configToDelete) { config in
                Button("取消", role: .cancel) { }
                Button("刪除", role: .destructive) {
                    viewModel.removeConfig(config)
                }
            } message: { config in
                Text("確定要刪除同步任務 '\(config.localFolderPath)' 到 '\(config.bucketName)/\(config.prefix)' 嗎？")
            }
            .sheet(isPresented: $showHistoryDetails, onDismiss: {
                selectedHistory = nil
            }) {
                if let history = selectedHistory {
                    SyncHistoryDetailView(
                        history: history,
                        onClose: { showHistoryDetails = false }
                    )
                }
            }
        }
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateFormat = "HH:mm"  // 24 小時制
        return formatter
    }
    
    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.dateFormat = "yyyy-MM-dd HH:mm"  // 24 小時制
        return formatter
    }
}

#Preview {
    SyncView(viewModel: SyncViewModel(accessKey: "", secretKey: "", region: ""))
}