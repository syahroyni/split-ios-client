//
//  LocalhostSplitFactory.swift
//  Split
//
//  Created by Javier L. Avrudsky on 14/02/2019.
//  Copyright © 2019 Split. All rights reserved.
//

import Foundation

///
/// SplitFactory implementation for Localhost mode
///
/// This mode is intended to use during development.
/// Check LocalhostSplitClient class for more information
///  - seealso:
/// [Split iOS SDK](https://docs.split.io/docs/ios-sdk-overview#section-localhost)
///
public class LocalhostSplitFactory: NSObject, SplitFactory {

    @objc public static var sdkVersion: String {
        return Version.semantic
    }

    private let localhostClient: SplitClient
    private let localhostManager: SplitManager
    private let eventsManager: SplitEventsManager
    private let splitsStorage: SplitsStorage

    public var client: SplitClient {
        return localhostClient
    }

    public var manager: SplitManager {
        return localhostManager
    }

    public var version: String {
        return Version.sdk
    }

    init(key: Key, config: SplitClientConfig, bundle: Bundle) {
        Logger.d("Initializing localhost mode")
        eventsManager = DefaultSplitEventsManager(config: config)
        eventsManager.start()
        let dataFolderName = SplitDatabaseHelper.sanitizeForFolderName(config.localhostDataFolder)
        let fileStorage = FileStorage(dataFolderName: dataFolderName)

        var storageConfig = YamlSplitStorageConfig()
        storageConfig.refreshInterval = config.offlineRefreshRate

        splitsStorage = LocalhostSplitsStorage(fileStorage: fileStorage,
                                          config: storageConfig,
                                          eventsManager: eventsManager,
                                          dataFolderName: dataFolderName,
                                          splitsFileName: config.splitFile,
                                          bundle: bundle)

        localhostClient = LocalhostSplitClient(key: key, splitsStorage: splitsStorage,
                                               eventsManager: eventsManager)
        eventsManager.executorResources.client = localhostClient
        localhostManager = DefaultSplitManager(splitsStorage: splitsStorage)
    }
}
