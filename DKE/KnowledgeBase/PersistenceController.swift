import CoreData
import Foundation

/// Manages the Core Data stack for the DKE app.
///
/// Uses a programmatic `NSManagedObjectModel` (see ``DKECoreDataModel``)
/// and stores its SQLite database under
/// `~/Library/Application Support/DKE/DKE.sqlite`.
final class PersistenceController {

    // MARK: - Singleton

    /// The shared persistence controller for production use.
    static let shared = PersistenceController()

    /// A persistence controller pre-loaded with sample data, intended for
    /// SwiftUI previews and unit tests.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // -- Sample Session --
        let session = SessionMO(entity: DKECoreDataModel.shared.entitiesByName["Session"]!,
                                insertInto: context)
        session.id = UUID()
        session.title = "Sample Domain Expert Interview"
        session.date = Date()
        session.mode = SessionMode.virtual.rawValue

        // -- Sample TranscriptSegment --
        let segment = TranscriptSegmentMO(entity: DKECoreDataModel.shared.entitiesByName["TranscriptSegment"]!,
                                          insertInto: context)
        segment.id = UUID()
        segment.text = "When we handle a claim, the first thing we always check is the policy status."
        segment.speaker = "Domain Expert"
        segment.startTime = 0.0
        segment.endTime = 5.2
        segment.session = session

        // -- Sample KnowledgeAtom --
        let atom = KnowledgeAtomMO(entity: DKECoreDataModel.shared.entitiesByName["KnowledgeAtom"]!,
                                   insertInto: context)
        atom.id = UUID()
        atom.content = "The first step in claim processing is verifying the policy status."
        atom.category = KnowledgeCategory.process.rawValue
        atom.sourceQuote = "the first thing we always check is the policy status"
        atom.speaker = "Domain Expert"
        atom.confidence = ConfidenceLevel.high.rawValue
        atom.tags = ["claims", "process", "policy"]
        atom.timestamp = Date()
        atom.session = session

        // -- Sample ModelConfig --
        let modelConfig = ModelConfigMO(entity: DKECoreDataModel.shared.entitiesByName["ModelConfig"]!,
                                        insertInto: context)
        modelConfig.id = UUID()
        modelConfig.name = "Local Llama 3"
        modelConfig.modelType = ModelType.ollama.rawValue
        modelConfig.endpoint = "http://localhost:11434"
        modelConfig.modelIdentifier = "llama3"
        modelConfig.taskCompatibility = [DKETask.analysis.rawValue, DKETask.nudgeGeneration.rawValue]

        do {
            try context.save()
        } catch {
            fatalError("PersistenceController.preview: failed to save sample data – \(error)")
        }

        return controller
    }()

    // MARK: - Container

    /// The underlying `NSPersistentContainer` backed by the programmatic model.
    let container: NSPersistentContainer

    // MARK: - Initializer

    /// Creates a new persistence controller.
    ///
    /// - Parameter inMemory: When `true`, the store is kept entirely in memory
    ///   (useful for previews and tests). Defaults to `false`.
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DKE",
                                          managedObjectModel: DKECoreDataModel.shared)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            let storeURL = PersistenceController.storeURL
            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            description.setOption(true as NSNumber,
                                  forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber,
                                  forKey: NSInferMappingModelAutomaticallyOption)
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("PersistenceController: failed to load persistent stores – \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Background Context

    /// Returns a new background `NSManagedObjectContext` tied to the
    /// persistent store coordinator.
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Store URL

    /// The file URL for the SQLite database.
    ///
    /// Resolves to `~/Library/Application Support/DKE/DKE.sqlite`,
    /// creating the directory if necessary.
    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("DKE", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory,
                                                        withIntermediateDirectories: true)
            } catch {
                fatalError("PersistenceController: unable to create store directory – \(error)")
            }
        }

        return directory.appendingPathComponent("DKE.sqlite")
    }
}
