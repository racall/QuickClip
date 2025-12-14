//
//  用户统计管理器
//  快速剪贴
//
//  创建者：Brian He（2025/12/13）
//

import Foundation
import CloudKit
import CryptoKit

/// 用户统计管理器
/// 负责上传匿名使用统计数据到 CloudKit Public Database
@MainActor
final class UsageStatsManager {

    // MARK: - 属性

    private let container: CKContainer
    private let publicDatabase: CKDatabase

    /// UserDefaults 键
    private let recordNameKey = "userStatsRecordName"

    // MARK: - 初始化

    init() {
        self.container = CKContainer(identifier: "iCloud.io.0os.QuickClip")
        self.publicDatabase = container.publicCloudDatabase
    }

    // MARK: - 公开接口

    /// 上传或更新统计数据（三层检查机制）
    func uploadOrUpdateStats() async throws {
        // 第一层：尝试使用本地缓存的recordName
        if let recordName = UserDefaults.standard.string(forKey: recordNameKey) {
            do {
                try await updateExistingRecord(recordName: recordName)
                print("✅ 用户统计数据已更新（使用缓存recordName）")
                return
            } catch let error as CKError where error.code == .unknownItem {
                print("⚠️ 本地缓存的recordName无效，清除缓存")
                UserDefaults.standard.removeObject(forKey: recordNameKey)
                // 继续向下执行第二层检查
            }
        }

        // 第二层：查询CloudKit是否已有该uid的记录
        let userRecordID = try await container.userRecordID()
        let uid = md5(userRecordID.recordName)

        if let existingRecord = try await queryRecordByUID(uid: uid) {
            // 找到了已有记录，保存recordName并更新
            let recordName = existingRecord.recordID.recordName
            UserDefaults.standard.set(recordName, forKey: recordNameKey)
            print("✅ 找到已有记录，恢复本地缓存: \(recordName)")

            // 更新记录
            try await updateExistingRecord(recordName: recordName)
            print("✅ 用户统计数据已更新（从CloudKit恢复）")
            return
        }

        // 第三层：确实是新用户，创建新记录
        try await createNewRecord()
        print("✅ 用户统计数据已创建（新用户）")
    }

    // MARK: - 私有方法

    /// 根据uid查询CloudKit中是否已有记录
    private func queryRecordByUID(uid: String) async throws -> CKRecord? {
        let predicate = NSPredicate(format: "uid == %@", uid)
        let query = CKQuery(recordType: "UsingUsers", predicate: predicate)

        let results = try await publicDatabase.records(matching: query)

        // 返回第一条匹配的记录（理论上只应该有一条）
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                return record
            }
        }

        return nil
    }

    /// 创建新的统计记录（首次启动）
    private func createNewRecord() async throws {
        // 1. 获取 userRecordID
        let userRecordID = try await container.userRecordID()
        let recordName = userRecordID.recordName

        // 2. 计算 MD5 作为 uid
        let uid = md5(recordName)

        // 3. 获取系统和 App 信息
        let osVersion = getOSVersion()
        let appVersion = getAppVersion()
        let now = Date()

        // 4. 获取 APNs Device Token（如果有）
        let deviceToken = PushNotificationManager.shared.deviceToken

        // 5. 创建 CloudKit 记录
        let record = CKRecord(recordType: "UsingUsers")
        record["uid"] = uid
        record["os"] = osVersion
        record["sv"] = appVersion
        record["firstSendDate"] = now
        record["sendDate"] = now
        record["token"] = deviceToken  // APNs Device Token

        // 6. 保存到 CloudKit Public Database
        let savedRecord = try await publicDatabase.save(record)

        // 6. 保存 recordName 到 UserDefaults
        UserDefaults.standard.set(savedRecord.recordID.recordName, forKey: recordNameKey)

        print("📊 统计数据已创建: uid=\(uid), os=\(osVersion), sv=\(appVersion)")
    }

    /// 更新已有的统计记录（后续启动）
    private func updateExistingRecord(recordName: String) async throws {
        // 1. 获取已有记录
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await publicDatabase.record(for: recordID)

        // 2. 更新字段（uid 和 firstSendDate 保持不变）
        record["os"] = getOSVersion()
        record["sv"] = getAppVersion()
        record["sendDate"] = Date()

        // 3. 更新 APNs Device Token（无论是否为nil都更新）
        // 如果当前有token就更新，如果没有就保持原值或设为nil（后续会通过监听更新）
        record["token"] = PushNotificationManager.shared.deviceToken

        // 4. 保存到 CloudKit
        _ = try await publicDatabase.save(record)

        let tokenStatus = PushNotificationManager.shared.deviceToken ?? "nil"
        print("📊 统计数据已更新: os=\(getOSVersion()), sv=\(getAppVersion()), token=\(tokenStatus)")
    }

    /// 获取系统版本
    private func getOSVersion() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return osVersion
    }

    /// 获取 App 版本号
    private func getAppVersion() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return appVersion
    }

    /// 计算字符串的 MD5 哈希值
    private func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
