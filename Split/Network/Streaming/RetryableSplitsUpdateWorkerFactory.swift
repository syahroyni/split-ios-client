//
//  SplitsWorkerFactory.swift
//  Split
//
//  Created by Javier L. Avrudsky on 21/09/2020.
//  Copyright © 2020 Split. All rights reserved.
//

import Foundation

/// Helper to allow unit testing of some features by stubbing it
protocol MySegmentsSyncWorkerFactory {
    func createRetryableMySegmentsSyncWorker(forKey key: String,
                                             avoidCache: Bool,
                                             eventsManager: SplitEventsManager) -> RetryableSyncWorker

    func createPeriodicMySegmentsSyncWorker(forKey key: String,
                                            eventsManager: SplitEventsManager) -> PeriodicSyncWorker
}

protocol SyncWorkerFactory {

    func createRetryableSplitsSyncWorker() -> RetryableSyncWorker

    func createPeriodicSplitsSyncWorker() -> PeriodicSyncWorker

    func createRetryableSplitsUpdateWorker(changeNumber: Int64,
                                           reconnectBackoffCounter: ReconnectBackoffCounter
    ) -> RetryableSyncWorker

    func createPeriodicImpressionsRecorderWorker(syncHelper: ImpressionsRecorderSyncHelper?) -> PeriodicRecorderWorker

    func createImpressionsRecorderWorker(syncHelper: ImpressionsRecorderSyncHelper?) -> RecorderWorker

    func createImpressionsCountRecorderWorker() -> RecorderWorker

    func createPeriodicImpressionsCountRecorderWorker() -> PeriodicRecorderWorker

    func createPeriodicEventsRecorderWorker(syncHelper: EventsRecorderSyncHelper?) -> PeriodicRecorderWorker

    func createEventsRecorderWorker(syncHelper: EventsRecorderSyncHelper?) -> RecorderWorker

    func createTelemetryConfigRecorderWorker() -> RecorderWorker?

    func createTelemetryStatsRecorderWorker() -> RecorderWorker?

    func createPeriodicTelemetryStatsRecorderWorker() -> PeriodicRecorderWorker?
}

class DefaultSyncWorkerFactory: SyncWorkerFactory {

    private let storageContainer: SplitStorageContainer
    private let apiFacade: SplitApiFacade
    private let splitConfig: SplitClientConfig
    private let splitChangeProcessor: SplitChangeProcessor
    private let userKey: String
    private let eventsManager: SplitEventsManager
    private let splitsFilterQueryString: String
    private let telemetryProducer: TelemetryProducer?

    init(userKey: String,
         splitConfig: SplitClientConfig,
         splitsFilterQueryString: String,
         apiFacade: SplitApiFacade,
         storageContainer: SplitStorageContainer,
         splitChangeProcessor: SplitChangeProcessor,
         eventsManager: SplitEventsManager) {

        self.userKey = userKey
        self.splitConfig = splitConfig
        self.splitsFilterQueryString = splitsFilterQueryString
        self.apiFacade = apiFacade
        self.storageContainer = storageContainer
        self.splitChangeProcessor = splitChangeProcessor
        self.eventsManager = eventsManager
        self.telemetryProducer = storageContainer.telemetryStorage
    }

    func createRetryableSplitsSyncWorker() -> RetryableSyncWorker {
        let backoffCounter = DefaultReconnectBackoffCounter(backoffBase: splitConfig.generalRetryBackoffBase)
        return RetryableSplitsSyncWorker(splitFetcher: apiFacade.splitsFetcher,
                                         splitsStorage: storageContainer.splitsStorage,
                                         splitChangeProcessor: splitChangeProcessor,
                                         cacheExpiration: splitConfig.cacheExpirationInSeconds,
                                         defaultQueryString: splitsFilterQueryString,
                                         eventsManager: eventsManager,
                                         reconnectBackoffCounter: backoffCounter)
    }

    func createRetryableSplitsUpdateWorker(changeNumber: Int64,
                                           reconnectBackoffCounter: ReconnectBackoffCounter) -> RetryableSyncWorker {
        return RetryableSplitsUpdateWorker(splitsFetcher: apiFacade.splitsFetcher,
                                           splitsStorage: storageContainer.splitsStorage,
                                           splitChangeProcessor: splitChangeProcessor,
                                           changeNumber: changeNumber, eventsManager: eventsManager,
                                           reconnectBackoffCounter: reconnectBackoffCounter)
    }

    func createPeriodicSplitsSyncWorker() -> PeriodicSyncWorker {
        return  PeriodicSplitsSyncWorker(
            splitFetcher: apiFacade.splitsFetcher, splitsStorage: storageContainer.splitsStorage,
            splitChangeProcessor: splitChangeProcessor,
            timer: DefaultPeriodicTimer(interval: splitConfig.featuresRefreshRate), eventsManager: eventsManager)
    }

    func createPeriodicImpressionsRecorderWorker(syncHelper: ImpressionsRecorderSyncHelper?) -> PeriodicRecorderWorker {
        let impressionWorker = ImpressionsRecorderWorker(impressionsStorage: storageContainer.impressionsStorage,
                                                         impressionsRecorder: apiFacade.impressionsRecorder,
                                                         impressionsPerPush: Int(splitConfig.impressionsChunkSize),
                                                         impressionsSyncHelper: syncHelper)

        let timer = DefaultPeriodicTimer(deadline: 0, interval: splitConfig.impressionRefreshRate)
        return DefaultPeriodicRecorderWorker(timer: timer, recorderWorker: impressionWorker)
    }

    func createImpressionsRecorderWorker(syncHelper: ImpressionsRecorderSyncHelper?) -> RecorderWorker {
        return ImpressionsRecorderWorker(impressionsStorage: storageContainer.impressionsStorage,
                                         impressionsRecorder: apiFacade.impressionsRecorder,
                                         impressionsPerPush: Int(splitConfig.impressionsChunkSize),
                                         impressionsSyncHelper: syncHelper)
    }

    func createImpressionsCountRecorderWorker() -> RecorderWorker {
        return ImpressionsCountRecorderWorker(countsStorage: storageContainer.impressionsCountStorage,
                                              countsRecorder: apiFacade.impressionsCountRecorder)
    }

    func createPeriodicImpressionsCountRecorderWorker() -> PeriodicRecorderWorker {
        let recorderWorker = ImpressionsCountRecorderWorker(countsStorage: storageContainer.impressionsCountStorage,
                                                            countsRecorder: apiFacade.impressionsCountRecorder)
        let timer = DefaultPeriodicTimer(deadline: 0, interval: splitConfig.impressionsCountsRefreshRate)
        return DefaultPeriodicRecorderWorker(timer: timer, recorderWorker: recorderWorker)
    }

    func createPeriodicEventsRecorderWorker(syncHelper: EventsRecorderSyncHelper?) -> PeriodicRecorderWorker {
        let eventsWorker = EventsRecorderWorker(eventsStorage: storageContainer.eventsStorage,
                                                eventsRecorder: apiFacade.eventsRecorder,
                                                eventsPerPush: Int(splitConfig.eventsPerPush),
                                                eventsSyncHelper: syncHelper)

        let timer = DefaultPeriodicTimer(deadline: splitConfig.eventsFirstPushWindow,
                                         interval: splitConfig.eventsPushRate)
        return DefaultPeriodicRecorderWorker(timer: timer, recorderWorker: eventsWorker)
    }

    func createEventsRecorderWorker(syncHelper: EventsRecorderSyncHelper?) -> RecorderWorker {
        return EventsRecorderWorker(eventsStorage: storageContainer.eventsStorage,
                                    eventsRecorder: apiFacade.eventsRecorder,
                                    eventsPerPush: Int(splitConfig.eventsPerPush),
                                    eventsSyncHelper: syncHelper)

    }

    func createTelemetryConfigRecorderWorker() -> RecorderWorker? {

        guard let telemetryStorage = storageContainer.telemetryStorage else {
            return nil
        }

        guard let telemetryConfigRecorder = apiFacade.telemetryConfigRecorder else {
            return nil
        }

        return TelemetryConfigRecorderWorker(telemetryConfigRecorder: telemetryConfigRecorder,
                                             splitClientConfig: splitConfig,
                                             telemetryConsumer: telemetryStorage)
    }

    func createTelemetryStatsRecorderWorker() -> RecorderWorker? {

        guard let telemetryStorage = storageContainer.telemetryStorage else {
            return nil
        }

        guard let telemetryStatsRecorder = apiFacade.telemetryStatsRecorder else {
            return nil
        }

        return TelemetryStatsRecorderWorker(telemetryStatsRecorder: telemetryStatsRecorder,
                                            telemetryConsumer: telemetryStorage,
                                            splitsStorage: storageContainer.splitsStorage,
                                            mySegmentsStorage: storageContainer.mySegmentsStorage)
    }

    func createPeriodicTelemetryStatsRecorderWorker() -> PeriodicRecorderWorker? {

        guard let telemetryStorage = storageContainer.telemetryStorage else {
            return nil
        }

        guard let telemetryStatsRecorder = apiFacade.telemetryStatsRecorder else {
            return nil
        }

        let telemetryStatsWorker = TelemetryStatsRecorderWorker(telemetryStatsRecorder: telemetryStatsRecorder,
                                                                telemetryConsumer: telemetryStorage,
                                                                splitsStorage: storageContainer.splitsStorage,
                                                                mySegmentsStorage: storageContainer.mySegmentsStorage)

        let timer = DefaultPeriodicTimer(deadline: splitConfig.internalTelemetryRefreshRate,
                                         interval: splitConfig.internalTelemetryRefreshRate)

        return DefaultPeriodicRecorderWorker(timer: timer, recorderWorker: telemetryStatsWorker)
    }
}

class DefaultMySegmentsSyncWorkerFactory: MySegmentsSyncWorkerFactory {
    let splitConfig: SplitClientConfig
    let mySegmentsStorage: MySegmentsStorage
    let mySegmentsFetcher: HttpMySegmentsFetcher
    let telemetryProducer: TelemetryProducer?

    init(splitConfig: SplitClientConfig,
         mySegmentsStorage: MySegmentsStorage,
         mySegmentsFetcher: HttpMySegmentsFetcher,
         telemetryProducer: TelemetryProducer?) {
        self.splitConfig = splitConfig
        self.mySegmentsStorage = mySegmentsStorage
        self.mySegmentsFetcher = mySegmentsFetcher
        self.telemetryProducer = telemetryProducer
    }

    func createRetryableMySegmentsSyncWorker(forKey key: String,
                                             avoidCache: Bool,
                                             eventsManager: SplitEventsManager) -> RetryableSyncWorker {

        let backoffBase =  splitConfig.generalRetryBackoffBase
        let mySegmentsBackoffCounter = DefaultReconnectBackoffCounter(backoffBase: backoffBase)
        let byKeyStorage = DefaultByKeyMySegmentsStorage(mySegmentsStorage: mySegmentsStorage, userKey: key)
        return RetryableMySegmentsSyncWorker(userKey: key,
                                             mySegmentsFetcher: mySegmentsFetcher,
                                             mySegmentsStorage: byKeyStorage,
                                             telemetryProducer: telemetryProducer,
                                             eventsManager: eventsManager,
                                             reconnectBackoffCounter: mySegmentsBackoffCounter,
                                             avoidCache: avoidCache)
    }

    func createPeriodicMySegmentsSyncWorker(forKey key: String,
                                            eventsManager: SplitEventsManager) -> PeriodicSyncWorker {
        let byKeyStorage = DefaultByKeyMySegmentsStorage(mySegmentsStorage: mySegmentsStorage, userKey: key)
        return PeriodicMySegmentsSyncWorker(
            userKey: key, mySegmentsFetcher: mySegmentsFetcher,
            mySegmentsStorage: byKeyStorage,
            telemetryProducer: telemetryProducer,
            timer: DefaultPeriodicTimer(interval: splitConfig.segmentsRefreshRate),
            eventsManager: eventsManager)
    }
}
