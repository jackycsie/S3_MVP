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

@MainActor
class SyncViewModel: ObservableObject {
    @Published var configs: [SyncConfig] = []
    @Published var newConfig = SyncConfig(localFolderPath: "", bucketName: "", prefix: "", syncTime: Date())
    @Published var selectedBucket: String = ""
    @Published var availableBuckets: [String] = []
    @Published var syncStatus: String = ""
    @Published var isLoading = false
    @Published var lastSyncDate: Date? = nil
    @Published var isBackgroundSyncEnabled = true
    
    private var syncTimer: Timer? = nil
    
    #if os(iOS)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    let accessKey: String
    let secretKey: String
    let region: String
    
    init(accessKey: String, secretKey: String, region: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        
        print("初始化 SyncViewModel")
        
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
        
        // 啟動同步計時器
        startSyncTimer()
    }
    
    deinit {
        // 直接訪問並停止計時器，避免調用 @MainActor 方法
        syncTimer?.invalidate()
        syncTimer = nil
        
        #if os(iOS)
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        #endif
    }
    
    // 啟動定時同步計時器
    func startSyncTimer() {
        log("啟動同步計時器")
        stopSyncTimer() // 確保先停止舊的計時器
        
        // 每分鐘檢查一次是否需要同步
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.log("計時器觸發檢查...")
            Task { [weak self] in
                await self?.checkScheduledSync()
            }
        }
        
        // 立即執行一次檢查，不用等待第一個計時器間隔
        Task { [weak self] in
            self?.log("初始檢查同步任務...")
            await self?.checkScheduledSync()
        }
        
        log("同步計時器已啟動，間隔: 60秒")
    }
    
    // 停止定時同步計時器
    func stopSyncTimer() {
        print("停止同步計時器")
        syncTimer?.invalidate()
        syncTimer = nil
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
        log("當前時間: \(currentHour):\(currentMinute)")
        
        // 記錄所有啟用的配置及其同步時間
        for config in configs where config.isEnabled {
            let syncHour = calendar.component(.hour, from: config.syncTime)
            let syncMinute = calendar.component(.minute, from: config.syncTime)
            log("檢查配置: \(config.localFolderPath) -> \(config.bucketName)/\(config.prefix), 同步時間: \(syncHour):\(syncMinute)")
            
            // 檢查是否到達同步時間（允許 1 分鐘誤差）
            if currentHour == syncHour && abs(currentMinute - syncMinute) <= 1 {
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
                log("✗ 時間不匹配，跳過同步: \(syncHour):\(syncMinute) vs 當前 \(currentHour):\(currentMinute)")
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
    
    func syncFolder(config: SyncConfig) async {
        log("開始同步文件夾: \(config.localFolderPath) -> \(config.bucketName)/\(config.prefix)")
        
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
            
            for file in files {
                let localPath = "\(config.localFolderPath)/\(file)"
                var isDir: ObjCBool = false
                
                if fileManager.fileExists(atPath: localPath, isDirectory: &isDir) && !isDir.boolValue {
                    log("同步文件: \(file)")
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
                }
            }
            
            syncStatus = "同步完成"
            log("同步任務完成: \(config.localFolderPath)")
        } catch {
            syncStatus = "同步失敗: \(error.localizedDescription)"
            log("同步失敗: \(error.localizedDescription)")
        }
    }
    
    func toggleConfig(_ config: SyncConfig) {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index].isEnabled.toggle()
            saveConfigsToUserDefaults()  // 保存到 UserDefaults
        }
    }
    
    func removeConfig(_ config: SyncConfig) {
        configs.removeAll(where: { $0.id == config.id })
        saveConfigsToUserDefaults()  // 保存到 UserDefaults
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
        let timestamp = ISO8601DateFormatter().string(from: Date())
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
    
    var body: some View {
        NavigationStack {
            List {
                Section("現有同步任務") {
                    if viewModel.configs.isEmpty {
                        Text("無同步任務")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.configs) { config in
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
                                }
                                
                                if !viewModel.syncStatus.isEmpty && viewModel.syncStatus.contains(config.localFolderPath) {
                                    Text(viewModel.syncStatus)
                                        .font(.caption)
                                        .foregroundColor(viewModel.syncStatus.contains("失敗") ? .red : .green)
                                        .padding(.top, 4)
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
                
                if !viewModel.syncStatus.isEmpty && !viewModel.syncStatus.contains("/") {
                    Section("同步狀態") {
                        Text(viewModel.syncStatus)
                            .foregroundColor(viewModel.syncStatus.contains("失敗") ? .red : .green)
                    }
                }
                
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
        }
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    SyncView(viewModel: SyncViewModel(accessKey: "", secretKey: "", region: ""))
}