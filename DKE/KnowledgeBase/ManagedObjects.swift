import CoreData
import Foundation

// MARK: - SessionMO

/// Core Data managed object representing a knowledge-extraction session.
class SessionMO: NSManagedObject {

    // MARK: Stored Attributes

    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var date: Date
    @NSManaged var mode: String
    @NSManaged var audioFilePath: String?

    // MARK: Relationships

    @NSManaged var segments: NSSet?
    @NSManaged var knowledgeAtoms: NSSet?

    // MARK: Type-Safe Accessors

    var sessionMode: SessionMode {
        get { SessionMode(rawValue: mode) ?? .inPerson }
        set { mode = newValue.rawValue }
    }

    // MARK: Relationship Helpers

    var segmentsArray: [TranscriptSegmentMO] {
        let set = segments as? Set<TranscriptSegmentMO> ?? []
        return set.sorted { $0.startTime < $1.startTime }
    }

    var knowledgeAtomsArray: [KnowledgeAtomMO] {
        let set = knowledgeAtoms as? Set<KnowledgeAtomMO> ?? []
        return set.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Generated Accessors for segments

extension SessionMO {

    @objc(addSegmentsObject:)
    @NSManaged func addToSegments(_ value: TranscriptSegmentMO)

    @objc(removeSegmentsObject:)
    @NSManaged func removeFromSegments(_ value: TranscriptSegmentMO)

    @objc(addSegments:)
    @NSManaged func addToSegments(_ values: NSSet)

    @objc(removeSegments:)
    @NSManaged func removeFromSegments(_ values: NSSet)
}

// MARK: - Generated Accessors for knowledgeAtoms

extension SessionMO {

    @objc(addKnowledgeAtomsObject:)
    @NSManaged func addToKnowledgeAtoms(_ value: KnowledgeAtomMO)

    @objc(removeKnowledgeAtomsObject:)
    @NSManaged func removeFromKnowledgeAtoms(_ value: KnowledgeAtomMO)

    @objc(addKnowledgeAtoms:)
    @NSManaged func addToKnowledgeAtoms(_ values: NSSet)

    @objc(removeKnowledgeAtoms:)
    @NSManaged func removeFromKnowledgeAtoms(_ values: NSSet)
}

// MARK: - TranscriptSegmentMO

/// Core Data managed object representing a single segment of a transcript.
class TranscriptSegmentMO: NSManagedObject {

    // MARK: Stored Attributes

    @NSManaged var id: UUID
    @NSManaged var text: String
    @NSManaged var speaker: String?
    @NSManaged var startTime: Double
    @NSManaged var endTime: Double

    // MARK: Relationships

    @NSManaged var session: SessionMO
}

// MARK: - KnowledgeAtomMO

/// Core Data managed object representing a single extracted piece of domain knowledge.
class KnowledgeAtomMO: NSManagedObject {

    // MARK: Stored Attributes

    @NSManaged var id: UUID
    @NSManaged var content: String
    @NSManaged var category: String
    @NSManaged var sourceQuote: String?
    @NSManaged var speaker: String?
    @NSManaged var confidence: String
    @NSManaged var tags: [String]?
    @NSManaged var timestamp: Date

    // MARK: Relationships

    @NSManaged var session: SessionMO?

    // MARK: Type-Safe Accessors

    var knowledgeCategory: KnowledgeCategory {
        get { KnowledgeCategory(rawValue: category) ?? .process }
        set { category = newValue.rawValue }
    }

    var confidenceLevel: ConfidenceLevel {
        get { ConfidenceLevel(rawValue: confidence) ?? .medium }
        set { confidence = newValue.rawValue }
    }

    var tagsArray: [String] {
        get { tags ?? [] }
        set { tags = newValue }
    }
}

// MARK: - ModelConfigMO

/// Core Data managed object representing an AI model configuration.
class ModelConfigMO: NSManagedObject {

    // MARK: Stored Attributes

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var modelType: String
    @NSManaged var endpoint: String?
    @NSManaged var apiKey: String?
    @NSManaged var modelIdentifier: String
    @NSManaged var taskCompatibility: [String]?

    // MARK: Type-Safe Accessors

    var type: ModelType {
        get { ModelType(rawValue: modelType) ?? .ollama }
        set { modelType = newValue.rawValue }
    }

    var compatibleTasks: [DKETask] {
        get {
            (taskCompatibility ?? []).compactMap { DKETask(rawValue: $0) }
        }
        set {
            taskCompatibility = newValue.map(\.rawValue)
        }
    }
}
