//
//  Evaluator.swift
//  Split
//
//  Created by Natalia  Stele on 11/14/17.
//

import Foundation
// swiftlint:disable function_body_length
struct EvaluationResult {
    var treatment: String
    var label: String
    var changeNumber: Int64?
    var configuration: String?

    init(treatment: String, label: String, changeNumber: Int64? = nil, configuration: String? = nil) {
        self.treatment = treatment
        self.label = label
        self.changeNumber = changeNumber
        self.configuration = configuration
    }
}

struct EvalValues {
    let matchValue: Any?
    let matchingKey: String
    let bucketingKey: String?
    let attributes: [String: Any]?
}

// Components needed
struct EvalContext {
    let evaluator: Evaluator
    let mySegmentsStorage: MySegmentsStorage
}

protocol Evaluator {
    func evalTreatment(matchingKey: String, bucketingKey: String?,
                       splitName: String, attributes: [String: Any]?) throws -> EvaluationResult
}

class DefaultEvaluator: Evaluator {
    private let splitter: SplitterProtocol = Splitter.shared
    private let storageContainer: SplitStorageContainer


    init(storageContainer: SplitStorageContainer) {
        self.storageContainer = storageContainer
    }

    func evalTreatment(matchingKey: String, bucketingKey: String?,
                       splitName: String, attributes: [String: Any]?) throws -> EvaluationResult {

        guard let split = storageContainer.splitsStorage.get(name: splitName),
            split.status != .archived else {
                Logger.w("The SPLIT definition for '\(splitName)' has not been found")
                return EvaluationResult(treatment: SplitConstants.control, label: ImpressionsConstants.splitNotFound)
        }

        let changeNumber = split.changeNumber ?? -1
        let defaultTreatment  = split.defaultTreatment ?? SplitConstants.control
        if let killed = split.killed, killed {
            return EvaluationResult(treatment: defaultTreatment,
                                    label: ImpressionsConstants.killed,
                                    changeNumber: changeNumber,
                                    configuration: split.configurations?[defaultTreatment])
        }

        var bucketKey: String?
        var inRollOut: Bool = false
        var splitAlgo: Algorithm = Algorithm.legacy

        if let rawAlgo = split.algo, let algo = Algorithm.init(rawValue: rawAlgo) {
            splitAlgo = algo
        }

        bucketKey = !(bucketingKey ?? "").isEmpty() ? bucketingKey : matchingKey

        guard let conditions: [Condition] = split.conditions,
            let trafficAllocationSeed = split.trafficAllocationSeed,
            let seed = split.seed else {
                return EvaluationResult(treatment: SplitConstants.control, label: ImpressionsConstants.exception)
        }

        do {
            for condition in conditions {
                if !inRollOut && condition.conditionType == ConditionType.rollout {
                    if let trafficAllocation = split.trafficAllocation, trafficAllocation < 100 {
                        let bucket: Int64 = splitter.getBucket(seed: trafficAllocationSeed,
                                                               key: bucketKey!,
                                                               algo: splitAlgo)
                        if bucket > trafficAllocation {
                            return EvaluationResult(treatment: defaultTreatment,
                                                    label: ImpressionsConstants.notInSplit,
                                                    changeNumber: changeNumber,
                                                    configuration: split.configurations?[defaultTreatment])
                        }
                        inRollOut = true
                    }
                }

                //Return the first condition that match.
                let values = EvalValues(matchValue: matchingKey, matchingKey: matchingKey,
                                        bucketingKey: bucketKey, attributes: attributes)
                if try condition.match(values: values, context: getContext()) {
                    let key: Key = Key(matchingKey: matchingKey, bucketingKey: bucketKey)
                    let treatment = splitter.getTreatment(key: key, seed: seed, attributes: attributes,
                                                          partions: condition.partitions, algo: splitAlgo)
                    return EvaluationResult(treatment: treatment, label: condition.label!,
                                            changeNumber: changeNumber,
                                            configuration: split.configurations?[treatment])
                }
            }
            let result = EvaluationResult(treatment: defaultTreatment,
                                          label: ImpressionsConstants.noConditionMatched,
                                          changeNumber: changeNumber,
                                          configuration: split.configurations?[defaultTreatment])
            Logger.d("* Treatment for \(matchingKey) in \(split.name ?? "") is: \(result.treatment)")
            return result
        } catch EvaluatorError.matcherNotFound {
            Logger.e("The matcher has not been found")
            return EvaluationResult(treatment: SplitConstants.control, label: ImpressionsConstants.matcherNotFound,
                                    changeNumber: changeNumber)
        }
    }

    private func getContext() -> EvalContext {
        return EvalContext(evaluator: self, mySegmentsStorage: storageContainer.mySegmentsStorage)
    }
}
