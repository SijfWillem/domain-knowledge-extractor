import CoreData
import Foundation

/// Provides CRUD operations for all DKE Core Data entities.
///
/// ``DataStore`` wraps `NSManagedObjectContext` and exposes type-safe methods
/// for creating, reading, filtering, searching, and deleting managed objects.
/// All operations run synchronously on the caller's context; background work
/// should use a context obtained from ``PersistenceController/newBackgroundContext()``.
final class DataStore {

    // MARK: - Properties

    /// The managed object context used for all operations.
    private let context: NSManagedObjectContext

    /// Reference to the managed object model, used when inserting new objects.
    private let model: NSManagedObjectModel

    // MARK: - Initializer

    /// Creates a new data store backed by the given context.
    ///
    /// - Parameter context: The `NSManagedObjectContext` to operate on.
    ///   Defaults to the shared persistence controller's view context.
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        self.model = DKECoreDataModel.shared
    }

    // MARK: - Helpers

    /// Saves the context if there are uncommitted changes.
    ///
    /// - Throws: Any Core Data save error.
    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    /// Returns the `NSEntityDescription` for the given entity name.
    ///
    /// - Parameter name: The Core Data entity name (e.g. `"Session"`).
    /// - Returns: The entity description.
    /// - Precondition: The entity must exist in the model.
    private func entity(named name: String) -> NSEntityDescription {
        guard let entity = model.entitiesByName[name] else {
            fatalError("DataStore: entity '\(name)' not found in managed object model.")
        }
        return entity
    }

    // MARK: - Session CRUD

    /// Creates and returns a new session.
    ///
    /// - Parameters:
    ///   - title: A human-readable title for the session.
    ///   - mode: The session mode (in-person or virtual).
    ///   - audioFilePath: Optional file path to the session's audio recording.
    /// - Returns: The newly created `SessionMO`.
    @discardableResult
    func createSession(title: String,
                       mode: SessionMode,
                       audioFilePath: String? = nil) -> SessionMO {
        let session = SessionMO(entity: entity(named: "Session"), insertInto: context)
        session.id = UUID()
        session.title = title
        session.date = Date()
        session.mode = mode.rawValue
        session.audioFilePath = audioFilePath
        return session
    }

    /// Fetches all sessions, ordered by date descending (most recent first).
    ///
    /// - Returns: An array of `SessionMO`.
    /// - Throws: Any Core Data fetch error.
    func fetchAllSessions() throws -> [SessionMO] {
        let request = NSFetchRequest<SessionMO>(entityName: "Session")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    /// Deletes a session and (via cascade) its related segments and knowledge atoms.
    ///
    /// - Parameter session: The session to delete.
    func deleteSession(_ session: SessionMO) {
        context.delete(session)
    }

    // MARK: - TranscriptSegment CRUD

    /// Creates and returns a new transcript segment linked to a session.
    ///
    /// - Parameters:
    ///   - text: The transcribed text of the segment.
    ///   - speaker: Optional speaker label.
    ///   - startTime: Segment start time in seconds.
    ///   - endTime: Segment end time in seconds.
    ///   - session: The parent session.
    /// - Returns: The newly created `TranscriptSegmentMO`.
    @discardableResult
    func createTranscriptSegment(text: String,
                                 speaker: String? = nil,
                                 startTime: Double,
                                 endTime: Double,
                                 session: SessionMO) -> TranscriptSegmentMO {
        let segment = TranscriptSegmentMO(entity: entity(named: "TranscriptSegment"),
                                          insertInto: context)
        segment.id = UUID()
        segment.text = text
        segment.speaker = speaker
        segment.startTime = startTime
        segment.endTime = endTime
        segment.session = session
        return segment
    }

    /// Fetches all transcript segments for a given session, ordered by start time.
    ///
    /// - Parameter session: The session whose segments should be fetched.
    /// - Returns: An array of `TranscriptSegmentMO`.
    /// - Throws: Any Core Data fetch error.
    func fetchTranscriptSegments(for session: SessionMO) throws -> [TranscriptSegmentMO] {
        let request = NSFetchRequest<TranscriptSegmentMO>(entityName: "TranscriptSegment")
        request.predicate = NSPredicate(format: "session == %@", session)
        request.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
        return try context.fetch(request)
    }

    // MARK: - KnowledgeAtom CRUD

    /// Creates and returns a new knowledge atom.
    ///
    /// - Parameters:
    ///   - content: The extracted knowledge content.
    ///   - category: The knowledge category classification.
    ///   - sourceQuote: Optional original quote from the transcript.
    ///   - speaker: Optional speaker who provided the knowledge.
    ///   - confidence: The confidence level assigned to this atom.
    ///   - tags: A list of tags for classification and retrieval.
    ///   - session: Optional parent session.
    /// - Returns: The newly created `KnowledgeAtomMO`.
    @discardableResult
    func createKnowledgeAtom(content: String,
                             category: KnowledgeCategory,
                             sourceQuote: String? = nil,
                             speaker: String? = nil,
                             confidence: ConfidenceLevel,
                             tags: [String] = [],
                             session: SessionMO? = nil) -> KnowledgeAtomMO {
        let atom = KnowledgeAtomMO(entity: entity(named: "KnowledgeAtom"),
                                   insertInto: context)
        atom.id = UUID()
        atom.content = content
        atom.category = category.rawValue
        atom.sourceQuote = sourceQuote
        atom.speaker = speaker
        atom.confidence = confidence.rawValue
        atom.tags = tags
        atom.timestamp = Date()
        atom.session = session
        return atom
    }

    /// Fetches knowledge atoms with optional filters.
    ///
    /// All filter parameters are optional. When multiple filters are provided,
    /// they are combined with `AND` logic.
    ///
    /// - Parameters:
    ///   - category: Filter by knowledge category.
    ///   - confidence: Filter by confidence level.
    ///   - speaker: Filter by speaker (exact match).
    ///   - session: Filter by parent session.
    /// - Returns: An array of `KnowledgeAtomMO` matching the criteria.
    /// - Throws: Any Core Data fetch error.
    func fetchKnowledgeAtoms(category: KnowledgeCategory? = nil,
                             confidence: ConfidenceLevel? = nil,
                             speaker: String? = nil,
                             session: SessionMO? = nil) throws -> [KnowledgeAtomMO] {
        let request = NSFetchRequest<KnowledgeAtomMO>(entityName: "KnowledgeAtom")

        var predicates: [NSPredicate] = []

        if let category {
            predicates.append(NSPredicate(format: "category == %@", category.rawValue))
        }
        if let confidence {
            predicates.append(NSPredicate(format: "confidence == %@", confidence.rawValue))
        }
        if let speaker {
            predicates.append(NSPredicate(format: "speaker == %@", speaker))
        }
        if let session {
            predicates.append(NSPredicate(format: "session == %@", session))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return try context.fetch(request)
    }

    /// Searches knowledge atoms by a query string.
    ///
    /// The query is matched case- and diacritic-insensitively (`CONTAINS[cd]`)
    /// against the `content`, `sourceQuote`, and `speaker` fields. A match in
    /// any of the three fields is sufficient.
    ///
    /// - Parameter query: The search string.
    /// - Returns: An array of matching `KnowledgeAtomMO`.
    /// - Throws: Any Core Data fetch error.
    func searchKnowledgeAtoms(query: String) throws -> [KnowledgeAtomMO] {
        let request = NSFetchRequest<KnowledgeAtomMO>(entityName: "KnowledgeAtom")

        let contentPredicate = NSPredicate(format: "content CONTAINS[cd] %@", query)
        let sourcePredicate = NSPredicate(format: "sourceQuote CONTAINS[cd] %@", query)
        let speakerPredicate = NSPredicate(format: "speaker CONTAINS[cd] %@", query)

        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            contentPredicate,
            sourcePredicate,
            speakerPredicate
        ])

        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return try context.fetch(request)
    }

    /// Deletes a knowledge atom.
    ///
    /// - Parameter atom: The knowledge atom to delete.
    func deleteKnowledgeAtom(_ atom: KnowledgeAtomMO) {
        context.delete(atom)
    }

    // MARK: - ModelConfig CRUD

    /// Creates and returns a new model configuration.
    ///
    /// - Parameters:
    ///   - name: A human-readable name for the model config.
    ///   - modelType: The AI model backend type.
    ///   - endpoint: Optional endpoint URL string.
    ///   - apiKey: Optional API key for authentication.
    ///   - modelIdentifier: The model identifier used by the backend.
    ///   - taskCompatibility: The DKE tasks this model can handle.
    /// - Returns: The newly created `ModelConfigMO`.
    @discardableResult
    func createModelConfig(name: String,
                           modelType: ModelType,
                           endpoint: String? = nil,
                           apiKey: String? = nil,
                           modelIdentifier: String,
                           taskCompatibility: [DKETask] = []) -> ModelConfigMO {
        let config = ModelConfigMO(entity: entity(named: "ModelConfig"),
                                   insertInto: context)
        config.id = UUID()
        config.name = name
        config.modelType = modelType.rawValue
        config.endpoint = endpoint
        config.apiKey = apiKey
        config.modelIdentifier = modelIdentifier
        config.taskCompatibility = taskCompatibility.map(\.rawValue)
        return config
    }

    /// Fetches all model configurations, ordered by name.
    ///
    /// - Returns: An array of `ModelConfigMO`.
    /// - Throws: Any Core Data fetch error.
    func fetchAllModelConfigs() throws -> [ModelConfigMO] {
        let request = NSFetchRequest<ModelConfigMO>(entityName: "ModelConfig")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    /// Deletes a model configuration.
    ///
    /// - Parameter config: The model config to delete.
    func deleteModelConfig(_ config: ModelConfigMO) {
        context.delete(config)
    }
}
