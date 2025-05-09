//  PersistentStorageView.swift
//  ChromaTest2
//
//  Created by Nicholas Arner on 5/8/25.
//

import SwiftUI
import Chroma

struct PersistentStorageView: View {
    @State private var storagePath: String = {
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsURL.appendingPathComponent("ChromaTest2").path
        }
        return ""
    }()
    @State private var isInitialized = false
    @State private var collectionName = "" // For selected collection
    @State private var newCollectionName = "" // For creating new collection
    @State private var documentId = ""
    @State private var documentContent = ""
    @State private var statusMessage = ""
    @State private var queryResults = ""
    @State private var documents: [String] = []
    @State private var availableCollections: [String] = []
    @State private var isLoading = false
    
    // Add vector search state
    @State private var queryVector: String = "1.0, 0.0, 0.0"
    @State private var numResults: String = "5"
    @State private var searchResults = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage Configuration")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Storage Path:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("Storage Path", text: $storagePath)
                            .textFieldStyle(.roundedBorder)
                        
                        Text(storagePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Initialize Storage") {
                            print("Initializing storage at: \(storagePath)")
                            let success = initPersistentStorage(path: storagePath) == 1
                            isInitialized = success
                            updateStatus(success ? "Storage initialized" : "Failed to initialize storage")
                            if success {
                                detectCollections()
                                if !collectionName.isEmpty {
                                    refreshDocuments() // Refresh documents if a collection is selected
                                }
                            }
                        }
                        .buttonStyle(ActionButtonStyle(backgroundColor: .blue))
                        
                        Button("Close Storage") {
                            let success = closePersistentStorage() == 1
                            isInitialized = !success
                            if success {
                                resetFields()
                                updateStatus("Storage closed")
                            } else {
                                updateStatus("Failed to close storage")
                            }
                        }
                        .buttonStyle(ActionButtonStyle(backgroundColor: .red))
                        
                        if isInitialized {
                            Button(action: {
                                detectCollections()
                                if !collectionName.isEmpty {
                                    refreshDocuments()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh")
                                }
                            }
                            .buttonStyle(ActionButtonStyle(backgroundColor: .green))
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Collection Management")
                            .font(.headline)
                        
                        Spacer()
                        
                        if isInitialized {
                            Button(action: {
                                detectCollections()
                                if !collectionName.isEmpty {
                                    refreshDocuments()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if !availableCollections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select Collection:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("Collection", selection: $collectionName) {
                                Text("Select Collection").tag("")
                                ForEach(availableCollections, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                            .onChange(of: collectionName) { _, newValue in
                                print("Collection changed to: \(newValue)")
                                if !newValue.isEmpty {
                                    refreshDocuments()
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(availableCollections.isEmpty ? "Create First Collection:" : "Create New Collection:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("Collection Name", text: $newCollectionName)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Create Collection") {
                            guard !newCollectionName.isEmpty else { return }
                            
                            print("Creating collection: \(newCollectionName)")
                            let success = createPersistentCollection(name: newCollectionName, metadataJson: nil) == 1
                            if success {
                                availableCollections.append(newCollectionName)
                                collectionName = newCollectionName
                                newCollectionName = ""
                                refreshDocuments()
                                updateStatus("Collection created", autoHide: true)
                            } else {
                                updateStatus("Failed to create collection")
                            }
                        }
                        .buttonStyle(ActionButtonStyle(backgroundColor: .green))
                        .disabled(newCollectionName.isEmpty)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Document Management")
                            .font(.headline)
                        
                        Spacer()
                    }
                    
                    TextField("Document ID", text: $documentId)
                        .textFieldStyle(.roundedBorder)
                        .disabled(collectionName.isEmpty)
                    
                    TextEditor(text: $documentContent)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                        .disabled(collectionName.isEmpty)
                    
                    Button("Add Document") {
                        guard !collectionName.isEmpty else { return }
                        
                        let success = addPersistentDocument(
                            collectionName: collectionName,
                            documentId: documentId,
                            content: documentContent,
                            embedding: nil,
                            metadataJson: nil
                        ) == 1
                        updateStatus(
                            success ? "Document added" : "Failed to add document",
                            autoHide: success
                        )
                        if success {
                            documentId = ""
                            documentContent = ""
                            refreshDocuments()
                        }
                    }
                    .buttonStyle(ActionButtonStyle(backgroundColor: .blue))
                    .disabled(collectionName.isEmpty || documentId.isEmpty || documentContent.isEmpty)
                }
                .padding()
                .cornerRadius(10)
                .opacity(collectionName.isEmpty ? 0.7 : 1.0)
                
                // Add Vector Search Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Vector Search")
                        .font(.headline)
                    
                    if !collectionName.isEmpty {
                        if let dimension = try? loadEmbeddingDimension() {
                            Text("Vector Dimension: \(dimension)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Add embedding selector buttons
                        HStack {
                            Button("Use Embedding 1") {
                                if let vector = loadEmbedding(id: "1") {
                                    queryVector = vector.prefix(5).map { String(format: "%.2f", $0) }.joined(separator: ", ")
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Use Embedding 2") {
                                if let vector = loadEmbedding(id: "2") {
                                    queryVector = vector.prefix(5).map { String(format: "%.2f", $0) }.joined(separator: ", ")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Search Vector")
                                .fontWeight(.medium)
                            TextField("Enter comma-separated values (e.g. 1.0, 0.0, 0.0)", text: $queryVector)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        // Number of Results
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Number of Results")
                                .fontWeight(.medium)
                            TextField("Number of results", text: $numResults)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                        }
                        
                        Button("Search Similar Vectors") {
                            runVectorSearch()
                        }
                        .buttonStyle(ActionButtonStyle(backgroundColor: .blue))
                        .disabled(!isInitialized)
                        
                        if !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Search Results")
                                    .font(.headline)
                                    .padding(.top)
                                
                                ScrollView {
                                    Text(searchResults)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 200)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                    } else {
                        Text("Select a collection to perform vector search")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                
                documentsSection
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(10)
                }
            }
            .padding()
        }
        .onAppear {
            print("View appeared, checking storage...") // Debug print
            if isPersistentStorageInitialized() == 1 {
                print("Storage is initialized") // Debug print
                isInitialized = true
                detectCollections()
            } else {
                print("Storage is not initialized") // Debug print
            }
        }
        .onChange(of: isInitialized) { _, newValue in
            print("Storage initialization changed: \(newValue)") // Debug print
            if newValue {
                detectCollections()
            }
        }
    }
    
    private func refreshDocuments() {
        guard !collectionName.isEmpty else { return }
        
        isLoading = true
        print("Refreshing documents for collection: \(collectionName)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let collectionsURL = URL(fileURLWithPath: storagePath)
                .appendingPathComponent("collections")
                .appendingPathComponent(collectionName)
                .appendingPathComponent("documents")
            
            print("Checking documents at: \(collectionsURL.path)")
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: collectionsURL,
                    includingPropertiesForKeys: nil
                )
                
                let documentFiles = fileURLs.filter { $0.pathExtension == "txt" }
                print("Found document files: \(documentFiles)")
                
                let documentIds = documentFiles.map { $0.deletingPathExtension().lastPathComponent }
                print("Document IDs: \(documentIds)")
                
                if documentIds.isEmpty {
                    queryResults = "No documents found in '\(collectionName)'"
                    documents = []
                    isLoading = false
                    return
                }
                
                var formattedResults = "Documents in '\(collectionName)':\n\n"
                for (index, id) in documentIds.enumerated() {
                    formattedResults += "Document \(index + 1):\n"
                    formattedResults += "  ID: \(id)\n"
                    
                    let contentURL = collectionsURL.appendingPathComponent("\(id).txt")
                    if let content = try? String(contentsOf: contentURL, encoding: .utf8) {
                        formattedResults += "  Content: \(content)\n"
                    }
                    
                    let metadataURL = collectionsURL
                        .deletingLastPathComponent()
                        .appendingPathComponent("metadata.json")
                    
                    if let metadataData = try? Data(contentsOf: metadataURL),
                       let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
                        if let timestamp = metadata["created_at"] as? Double {
                            let date = Date(timeIntervalSince1970: timestamp)
                            let formatter = DateFormatter()
                            formatter.dateStyle = .medium
                            formatter.timeStyle = .short
                            formattedResults += "  Created: \(formatter.string(from: date))\n"
                        }
                    }
                    
                    formattedResults += "\n"
                }
                
                documents = documentIds
                queryResults = formattedResults
                
            } catch {
                print("Error reading documents: \(error)")
                queryResults = "Error reading documents: \(error.localizedDescription)"
                documents = []
            }
            isLoading = false
        }
    }
    
    private func updateStatus(_ message: String, isError: Bool = false, autoHide: Bool = false) {
        statusMessage = message
        
        if autoHide {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == message {
                    statusMessage = ""
                }
            }
        }
    }
    
    private func resetFields() {
        collectionName = ""
        documentId = ""
        documentContent = ""
        queryResults = ""
        documents = []
        availableCollections = []
    }
    
    private func detectCollections() {
        print("Detecting collections...") // Debug print
        
        let collectionsURL = URL(fileURLWithPath: storagePath).appendingPathComponent("collections")
        print("Collections URL: \(collectionsURL.path)")
        
        do {
            let storageContents = try FileManager.default.contentsOfDirectory(atPath: storagePath)
            print("Storage directory contents: \(storageContents)")
            
            if FileManager.default.fileExists(atPath: collectionsURL.path) {
                let collectionContents = try FileManager.default.contentsOfDirectory(atPath: collectionsURL.path)
                print("Collections directory contents: \(collectionContents)")
            }
        } catch {
            print("Error listing directory contents: \(error)")
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: collectionsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            let potentialCollections = contents
                .filter { url in
                    var isDirectory: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    print("Checking path: \(url.path) - exists: \(exists), isDirectory: \(isDirectory.boolValue)")
                    return isDirectory.boolValue
                }
                .map { $0.lastPathComponent }
            
            print("Found potential collections: \(potentialCollections)")
            
            availableCollections = potentialCollections.filter { name in
                let exists = persistentCollectionExists(collectionName: name) == 1
                print("Checking collection '\(name)': \(exists ? "valid" : "invalid")")
                
                let collectionPath = collectionsURL.appendingPathComponent(name)
                let documentsPath = collectionPath.appendingPathComponent("documents")
                let metadataPath = collectionPath.appendingPathComponent("metadata.json")
                
                var isDirectory: ObjCBool = false
                let hasDocuments = FileManager.default.fileExists(atPath: documentsPath.path, isDirectory: &isDirectory)
                let hasMetadata = FileManager.default.fileExists(atPath: metadataPath.path)
                
                print("""
                    Collection '\(name)' structure:
                    - Path: \(collectionPath.path)
                    - Documents exists: \(hasDocuments) (isDir: \(isDirectory.boolValue))
                    - Metadata exists: \(hasMetadata)
                    """)
                
                return exists
            }
            
            print("Valid collections: \(availableCollections)")
            
            if !availableCollections.isEmpty {
                if collectionName.isEmpty {
                    collectionName = availableCollections[0]
                    refreshDocuments() // Refresh the list
                }
            }
        } catch {
            print("Error detecting collections: \(error)")
            availableCollections = []
        }
    }
    
    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Documents in Collection")
                .font(.headline)
            
            if isLoading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Loading documents...")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if documents.isEmpty {
                Text(collectionName.isEmpty ? "Select a collection to view documents" : "No documents found in '\(collectionName)'")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Text(queryResults)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func loadEmbedding(id: String) -> [Float]? {
        let embeddingURL = URL(fileURLWithPath: storagePath)
            .appendingPathComponent("collections")
            .appendingPathComponent(collectionName)
            .appendingPathComponent("embeddings")
            .appendingPathComponent("\(id).json")
        
        do {
            print("Loading embedding from: \(embeddingURL.path)")
            let data = try Data(contentsOf: embeddingURL)
            let vector = try JSONDecoder().decode([Float].self, from: data)
            print("Successfully loaded embedding with \(vector.count) dimensions")
            return vector
        } catch {
            print("Error loading embedding: \(error)")
            return nil
        }
    }
    
    private func loadEmbeddingDimension() throws -> Int {
        let collectionsURL = URL(fileURLWithPath: storagePath)
            .appendingPathComponent("collections")
            .appendingPathComponent(collectionName)
            .appendingPathComponent("embeddings")
        
        let files = try FileManager.default.contentsOfDirectory(at: collectionsURL, includingPropertiesForKeys: nil)
        if let firstEmbedding = files.first {
            let data = try Data(contentsOf: firstEmbedding)
            let vector = try JSONDecoder().decode([Float].self, from: data)
            return vector.count
        }
        throw NSError(domain: "No embeddings found", code: -1)
    }
    
    private func inspectCollectionMetadata() -> String {
        let metadataURL = URL(fileURLWithPath: storagePath)
            .appendingPathComponent("collections")
            .appendingPathComponent(collectionName)
            .appendingPathComponent("metadata.json")
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let json = try JSONSerialization.jsonObject(with: data)
            print("Collection metadata: \(json)")
            return String(data: try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted), encoding: .utf8) ?? "Invalid JSON"
        } catch {
            print("Error reading metadata: \(error)")
            return "Error reading metadata"
        }
    }
    
    private func reinitializeCollection() -> Bool {
        print("Reinitializing collection...")
        
        // First, load all embeddings and documents
        let collectionsURL = URL(fileURLWithPath: storagePath)
            .appendingPathComponent("collections")
            .appendingPathComponent(collectionName)
        
        let embeddingsURL = collectionsURL.appendingPathComponent("embeddings")
        let documentsURL = collectionsURL.appendingPathComponent("documents")
        
        do {
            // Prepare metadata
            let metadata = [
                "dimension": 384,
                "created_at": Date().timeIntervalSince1970
            ] as [String : Any]
            
            let metadataJson = String(data: try JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)!
            
            // Reset storage and recreate collection
            print("Closing storage...")
            _ = closePersistentStorage()
            
            print("Reinitializing storage...")
            _ = initPersistentStorage(path: storagePath)
            
            print("Creating collection with metadata: \(metadataJson)")
            guard createPersistentCollection(name: collectionName, metadataJson: metadataJson) == 1 else {
                print("Failed to create collection")
                return false
            }
            
            // Load embeddings in sorted order
            let embeddingFiles = try FileManager.default.contentsOfDirectory(at: embeddingsURL, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            print("Found \(embeddingFiles.count) embeddings")
            
            var ids: [String] = []
            var embeddings: [[Float]] = []
            var metadatas: [String] = []
            
            // Load all embeddings first
            for embeddingFile in embeddingFiles {
                let documentId = embeddingFile.deletingPathExtension().lastPathComponent
                let documentFile = documentsURL.appendingPathComponent("\(documentId).txt")
                
                guard let embedding = try? JSONDecoder().decode([Float].self, from: Data(contentsOf: embeddingFile)),
                      let content = try? String(contentsOf: documentFile, encoding: .utf8) else {
                    print("Failed to load document \(documentId)")
                    continue
                }
                
                print("Processing document \(documentId) with \(embedding.count)-dimensional embedding")
                
                let docMetadata = ["content": content]
                let docMetadataJson = String(data: try JSONSerialization.data(withJSONObject: docMetadata), encoding: .utf8)!
                
                ids.append(documentId)
                embeddings.append(embedding)
                metadatas.append(docMetadataJson)
            }
            
            // Add all embeddings in one batch
            if !ids.isEmpty {
                print("Adding \(ids.count) documents with embeddings")
                let count = addPersistentEmbeddings(
                    collectionName: collectionName,
                    ids: ids,
                    embeddings: embeddings,
                    metadatas: metadatas
                )
                print("Successfully added \(count) documents")
                return count > 0
            }
            
            return false
        } catch {
            print("Error reinitializing collection: \(error)")
            return false
        }
    }
    
    private func runVectorSearch() {
        print("Running vector search for collection: \(collectionName)")
        
        guard let numResultsInt = UInt32(numResults) else {
            searchResults = "Invalid number of results"
            return
        }
        
        // APPROACH 1: Try using an existing embedding from the collection as query vector
        // This approach tests if the search functionality works at all
        do {
            print("TRYING APPROACH 1: Using existing embedding from collection")
            
            // Load the first embedding from the collection
            if let embedding = loadEmbedding(id: "1") {
                print("Using existing embedding from ID 1 with \(embedding.count) dimensions")
                
                // Introduce a small modification to avoid exact match
                var searchVector = embedding
                if !searchVector.isEmpty {
                    // Modify the first few elements slightly
                    for i in 0..<min(5, searchVector.count) {
                        searchVector[i] *= 0.98 // Perturb by a small amount
                    }
                }
                
                print("Slightly modified existing vector for search")
                
                if persistentCollectionExists(collectionName: collectionName) != 1 {
                    print("Collection does not exist in the persistent storage")
                    searchResults = "Error: Collection '\(collectionName)' not found in persistent storage"
                    return
                }
                
                let results = queryPersistentCollection(
                    collectionName: collectionName,
                    queryEmbedding: searchVector,
                    nResults: numResultsInt,
                    includeMetadata: true
                )
                
                print("Raw query results (approach 1): \(results)")
                
                if results.contains("ids\":[]") {
                    print("APPROACH 1 returned empty results, trying approach 2...")
                } else {
                    searchResults = formatQueryResults(results)
                    return
                }
            }
        } catch {
            print("Error in approach 1: \(error)")
        }
        
        // APPROACH 2: Fall back to the original approach with dimension adjustment
        print("TRYING APPROACH 2: Using adjusted user vector")
        
        // Parse the query vector from the text field
        let vectorComponents = queryVector.split(separator: ",").compactMap {
            Float($0.trimmingCharacters(in: .whitespaces))
        }
        
        guard !vectorComponents.isEmpty else {
            searchResults = "Invalid vector format"
            return
        }
        
        // Determine the expected dimension for the collection
        let expectedDimension: Int
        do {
            expectedDimension = try loadEmbeddingDimension()
            print("Collection '\(collectionName)' expected dimension: \(expectedDimension)")
        } catch {
            print("Could not determine embedding dimension: \(error)")
            // Check if there's any dimension we can use
            let dimension = Int(embeddingDimension(collectionName: collectionName))
            if dimension > 0 {
                expectedDimension = dimension
                print("Using collection's reported dimension: \(expectedDimension)")
            } else {
                searchResults = "Error: Could not determine embedding dimension"
                return
            }
        }
        
        // Handle dimension mismatch
        var searchVector = vectorComponents
        if vectorComponents.count != expectedDimension {
            print("⚠️ Dimension mismatch! Query vector has \(vectorComponents.count) dimensions, but collection expects \(expectedDimension) dimensions")
            
            if vectorComponents.count < expectedDimension {
                // Pad with zeros
                searchVector.append(contentsOf: Array(repeating: 0.0, count: expectedDimension - vectorComponents.count))
                print("⚠️ Query vector padded with zeros to reach \(expectedDimension) dimensions")
            } else {
                // Truncate
                searchVector = Array(vectorComponents.prefix(expectedDimension))
                print("⚠️ Query vector truncated to \(expectedDimension) dimensions")
            }
        }
        
        // Create a random component to mix with the search vector
        let randomVector = (0..<expectedDimension).map { _ in Float.random(in: -0.1...0.1) }
        
        // Mix the random component (10%) with the search vector (90%)
        for i in 0..<searchVector.count {
            searchVector[i] = searchVector[i] * 0.9 + (i < randomVector.count ? randomVector[i] * 0.1 : 0)
        }
        
        // Normalize the vector to improve search results
        let normalizedVector = normalizeVector(v: searchVector)
        print("Normalized query vector (first 5 elements): [\(normalizedVector.prefix(5).map { String(format: "%.4f", $0) }.joined(separator: ", "))...]")
        
        do {            
            print("Querying collection with normalized \(normalizedVector.count)-dimensional vector")
            
            // Try to validate the collection exists
            if persistentCollectionExists(collectionName: collectionName) != 1 {
                print("Collection does not exist in the persistent storage")
                searchResults = "Error: Collection '\(collectionName)' not found in persistent storage"
                return
            }
            
            let results = queryPersistentCollection(
                collectionName: collectionName,
                queryEmbedding: normalizedVector,
                nResults: numResultsInt,
                includeMetadata: true
            )
            
            print("Raw query results (approach 2): \(results)")
            searchResults = formatQueryResults(results)
        } catch {
            print("Error during search: \(error)")
            searchResults = "Error: \(error.localizedDescription)"
        }
    }
    
    private func formatQueryResults(_ jsonString: String) -> String {
        print("Formatting query results: \(jsonString)")
        guard let data = jsonString.data(using: .utf8) else {
            return "Invalid JSON format"
        }
        
        do {
            let result = try JSONDecoder().decode(QueryResult.self, from: data)
            
            var formattedResult = ""
            for (index, id) in result.ids.enumerated() {
                formattedResult += "Document \(index + 1):\n"
                formattedResult += "  ID: \(id)\n"
                
                // Load document content
                let documentsURL = URL(fileURLWithPath: storagePath)
                    .appendingPathComponent("collections")
                    .appendingPathComponent(collectionName)
                    .appendingPathComponent("documents")
                    .appendingPathComponent("\(id).txt")
                
                if let content = try? String(contentsOf: documentsURL, encoding: .utf8) {
                    formattedResult += "  Content: \(content)\n"
                }
                
                if let metadata = result.metadatas[safe: index] {
                    formattedResult += "  Metadata: \(metadata)\n"
                }
                
                if let distance = result.distances?[safe: index] {
                    formattedResult += "  Distance: \(String(format: "%.4f", distance))\n"
                }
                
                formattedResult += "\n"
            }
            return formattedResult.isEmpty ? "No documents found" : formattedResult
            
        } catch {
            print("Error parsing results: \(error)")
            return "Error parsing results: \(error.localizedDescription)"
        }
    }
}
