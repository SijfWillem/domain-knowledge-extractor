import CoreData

// MARK: - Programmatic Core Data Model

/// Builds the complete `NSManagedObjectModel` for DKE in code (no .xcdatamodeld).
enum DKECoreDataModel {

    /// The singleton managed-object model used by the persistence stack.
    static let shared: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        // ------------------------------------------------------------------
        // MARK: Entity Descriptions
        // ------------------------------------------------------------------

        let sessionEntity = NSEntityDescription()
        sessionEntity.name = "Session"
        sessionEntity.managedObjectClassName = NSStringFromClass(SessionMO.self)

        let segmentEntity = NSEntityDescription()
        segmentEntity.name = "TranscriptSegment"
        segmentEntity.managedObjectClassName = NSStringFromClass(TranscriptSegmentMO.self)

        let atomEntity = NSEntityDescription()
        atomEntity.name = "KnowledgeAtom"
        atomEntity.managedObjectClassName = NSStringFromClass(KnowledgeAtomMO.self)

        let modelConfigEntity = NSEntityDescription()
        modelConfigEntity.name = "ModelConfig"
        modelConfigEntity.managedObjectClassName = NSStringFromClass(ModelConfigMO.self)

        // ------------------------------------------------------------------
        // MARK: Session Attributes
        // ------------------------------------------------------------------

        let sessionID = NSAttributeDescription()
        sessionID.name = "id"
        sessionID.attributeType = .UUIDAttributeType
        sessionID.isOptional = false

        let sessionTitle = NSAttributeDescription()
        sessionTitle.name = "title"
        sessionTitle.attributeType = .stringAttributeType
        sessionTitle.isOptional = false

        let sessionDate = NSAttributeDescription()
        sessionDate.name = "date"
        sessionDate.attributeType = .dateAttributeType
        sessionDate.isOptional = false

        let sessionMode = NSAttributeDescription()
        sessionMode.name = "mode"
        sessionMode.attributeType = .stringAttributeType
        sessionMode.isOptional = false

        let sessionAudioFilePath = NSAttributeDescription()
        sessionAudioFilePath.name = "audioFilePath"
        sessionAudioFilePath.attributeType = .stringAttributeType
        sessionAudioFilePath.isOptional = true

        sessionEntity.properties = [
            sessionID, sessionTitle, sessionDate, sessionMode, sessionAudioFilePath
        ]

        // ------------------------------------------------------------------
        // MARK: TranscriptSegment Attributes
        // ------------------------------------------------------------------

        let segmentID = NSAttributeDescription()
        segmentID.name = "id"
        segmentID.attributeType = .UUIDAttributeType
        segmentID.isOptional = false

        let segmentText = NSAttributeDescription()
        segmentText.name = "text"
        segmentText.attributeType = .stringAttributeType
        segmentText.isOptional = false

        let segmentSpeaker = NSAttributeDescription()
        segmentSpeaker.name = "speaker"
        segmentSpeaker.attributeType = .stringAttributeType
        segmentSpeaker.isOptional = true

        let segmentStartTime = NSAttributeDescription()
        segmentStartTime.name = "startTime"
        segmentStartTime.attributeType = .doubleAttributeType
        segmentStartTime.isOptional = false
        segmentStartTime.defaultValue = 0.0

        let segmentEndTime = NSAttributeDescription()
        segmentEndTime.name = "endTime"
        segmentEndTime.attributeType = .doubleAttributeType
        segmentEndTime.isOptional = false
        segmentEndTime.defaultValue = 0.0

        segmentEntity.properties = [
            segmentID, segmentText, segmentSpeaker, segmentStartTime, segmentEndTime
        ]

        // ------------------------------------------------------------------
        // MARK: KnowledgeAtom Attributes
        // ------------------------------------------------------------------

        let atomID = NSAttributeDescription()
        atomID.name = "id"
        atomID.attributeType = .UUIDAttributeType
        atomID.isOptional = false

        let atomContent = NSAttributeDescription()
        atomContent.name = "content"
        atomContent.attributeType = .stringAttributeType
        atomContent.isOptional = false

        let atomCategory = NSAttributeDescription()
        atomCategory.name = "category"
        atomCategory.attributeType = .stringAttributeType
        atomCategory.isOptional = false

        let atomSourceQuote = NSAttributeDescription()
        atomSourceQuote.name = "sourceQuote"
        atomSourceQuote.attributeType = .stringAttributeType
        atomSourceQuote.isOptional = true

        let atomSpeaker = NSAttributeDescription()
        atomSpeaker.name = "speaker"
        atomSpeaker.attributeType = .stringAttributeType
        atomSpeaker.isOptional = true

        let atomConfidence = NSAttributeDescription()
        atomConfidence.name = "confidence"
        atomConfidence.attributeType = .stringAttributeType
        atomConfidence.isOptional = false

        let atomTags = NSAttributeDescription()
        atomTags.name = "tags"
        atomTags.attributeType = .transformableAttributeType
        atomTags.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
        atomTags.isOptional = true

        let atomTimestamp = NSAttributeDescription()
        atomTimestamp.name = "timestamp"
        atomTimestamp.attributeType = .dateAttributeType
        atomTimestamp.isOptional = false

        atomEntity.properties = [
            atomID, atomContent, atomCategory, atomSourceQuote,
            atomSpeaker, atomConfidence, atomTags, atomTimestamp
        ]

        // ------------------------------------------------------------------
        // MARK: ModelConfig Attributes
        // ------------------------------------------------------------------

        let modelConfigID = NSAttributeDescription()
        modelConfigID.name = "id"
        modelConfigID.attributeType = .UUIDAttributeType
        modelConfigID.isOptional = false

        let modelConfigName = NSAttributeDescription()
        modelConfigName.name = "name"
        modelConfigName.attributeType = .stringAttributeType
        modelConfigName.isOptional = false

        let modelConfigType = NSAttributeDescription()
        modelConfigType.name = "modelType"
        modelConfigType.attributeType = .stringAttributeType
        modelConfigType.isOptional = false

        let modelConfigEndpoint = NSAttributeDescription()
        modelConfigEndpoint.name = "endpoint"
        modelConfigEndpoint.attributeType = .stringAttributeType
        modelConfigEndpoint.isOptional = true

        let modelConfigAPIKey = NSAttributeDescription()
        modelConfigAPIKey.name = "apiKey"
        modelConfigAPIKey.attributeType = .stringAttributeType
        modelConfigAPIKey.isOptional = true

        let modelConfigIdentifier = NSAttributeDescription()
        modelConfigIdentifier.name = "modelIdentifier"
        modelConfigIdentifier.attributeType = .stringAttributeType
        modelConfigIdentifier.isOptional = false

        let modelConfigTaskCompat = NSAttributeDescription()
        modelConfigTaskCompat.name = "taskCompatibility"
        modelConfigTaskCompat.attributeType = .transformableAttributeType
        modelConfigTaskCompat.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
        modelConfigTaskCompat.isOptional = true

        modelConfigEntity.properties = [
            modelConfigID, modelConfigName, modelConfigType,
            modelConfigEndpoint, modelConfigAPIKey, modelConfigIdentifier,
            modelConfigTaskCompat
        ]

        // ------------------------------------------------------------------
        // MARK: Relationships
        // ------------------------------------------------------------------

        // Session ←→ TranscriptSegment  (one-to-many, cascade)
        let sessionToSegments = NSRelationshipDescription()
        let segmentToSession = NSRelationshipDescription()

        sessionToSegments.name = "segments"
        sessionToSegments.destinationEntity = segmentEntity
        sessionToSegments.inverseRelationship = segmentToSession
        sessionToSegments.minCount = 0
        sessionToSegments.maxCount = 0  // to-many
        sessionToSegments.deleteRule = .cascadeDeleteRule
        sessionToSegments.isOptional = true

        segmentToSession.name = "session"
        segmentToSession.destinationEntity = sessionEntity
        segmentToSession.inverseRelationship = sessionToSegments
        segmentToSession.minCount = 1
        segmentToSession.maxCount = 1  // to-one
        segmentToSession.deleteRule = .nullifyDeleteRule
        segmentToSession.isOptional = false

        // Session ←→ KnowledgeAtom  (one-to-many, cascade)
        let sessionToAtoms = NSRelationshipDescription()
        let atomToSession = NSRelationshipDescription()

        sessionToAtoms.name = "knowledgeAtoms"
        sessionToAtoms.destinationEntity = atomEntity
        sessionToAtoms.inverseRelationship = atomToSession
        sessionToAtoms.minCount = 0
        sessionToAtoms.maxCount = 0  // to-many
        sessionToAtoms.deleteRule = .cascadeDeleteRule
        sessionToAtoms.isOptional = true

        atomToSession.name = "session"
        atomToSession.destinationEntity = sessionEntity
        atomToSession.inverseRelationship = sessionToAtoms
        atomToSession.minCount = 0
        atomToSession.maxCount = 1  // to-one
        atomToSession.deleteRule = .nullifyDeleteRule
        atomToSession.isOptional = true

        // Append relationships to entity properties
        sessionEntity.properties += [sessionToSegments, sessionToAtoms]
        segmentEntity.properties += [segmentToSession]
        atomEntity.properties += [atomToSession]

        // ------------------------------------------------------------------
        // MARK: Assemble Model
        // ------------------------------------------------------------------

        model.entities = [sessionEntity, segmentEntity, atomEntity, modelConfigEntity]

        return model
    }()
}
