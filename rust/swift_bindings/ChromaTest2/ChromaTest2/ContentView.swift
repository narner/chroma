import SwiftUI
import Chroma

func listCollections(_ collections: [String]) -> String {
    var results: [String] = []
    
    func validateCollection(_ name: String) -> Bool {
        let metadataString = getCollectionMetadata(collectionName: name)
        guard !metadataString.isEmpty else { return false }
        
        // Try to parse metadata to verify collection is valid
        guard let data = metadataString.data(using: String.Encoding.utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return true
    }
    
    // Check each collection
    for name in collections {
        if validateCollection(name) {
            results.append(name)
        }
    }
    
    if results.isEmpty {
        return "No valid collections found"
    }
    
    return "Active Collections:\n" + results.joined(separator: "\n")
}

func formatQueryResults(_ jsonString: String) -> String {
    guard let data = jsonString.data(using: .utf8) else {
        return "Invalid JSON format"
    }
    
    do {
        let result = try JSONDecoder().decode(QueryResult.self, from: data)
        
        var formattedResult = ""
        for (index, id) in result.ids.enumerated() {
            formattedResult += "Document \(index + 1):\n"
            formattedResult += "  ID: \(id)\n"
            if let metadata = result.metadatas[safe: index] {
                formattedResult += "  Metadata: \(metadata)\n"
            }
            if let embeddings = result.embeddings?[safe: index] {
                formattedResult += "  Embedding: \(formatVector(embeddings))\n"
            }
            formattedResult += "\n"
        }
        return formattedResult.isEmpty ? "No documents found" : formattedResult
        
    } catch {
        return "Error parsing results: \(error.localizedDescription)"
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

func formatVector(_ vector: [Float]) -> String {
    return "[" + vector.map { String(format: "%.3f", $0) }.joined(separator: ", ") + "]"
}

struct CollectionMetadata: Codable {
    let description: String?
    let dimension: Int
    let created_at: TimeInterval
}

struct QueryResult: Codable {
    let ids: [String]
    let metadatas: [[String: String]]
    let embeddings: [[Float]]?
}

func getCollectionMetadata(collectionName: String) -> String {
    let query = queryCollection(
        collectionName: collectionName,
        queryEmbedding: [1.0, 0.0, 0.0],
        nResults: 1,
        includeMetadata: true
    )
    return query
}

struct ContentView: View {
    // MARK: - Demo data
    @State private var vectorA: [Float] = [1, 2, 3]
    @State private var vectorB: [Float] = [4, 5, 6]
    
    // MARK: - State
    @State private var version = "…"
    @State private var heartbeat: UInt64 = 0
    @State private var normA: [Float] = []
    @State private var l2: Float = 0
    @State private var cosine: Float = 0
    @State private var innerProd: Float = 0
    @State private var showCreateCollection = false
    @State private var showResetDatabase = false
    @State private var showAddDocument = false
    @State private var collectionsInfo = "..."
    @State private var selectedTab = 0
    @State private var queryResults = ""
    
    // MARK: - Collection management state
    @State private var collections: [String] = []
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Overview Tab
            VStack {
                InfoCard(title: "Chroma Status", content: [
                    ("Version", version),
                    ("Heartbeat", "\(heartbeat) ns")
                ])
                .padding()
                
                Divider()
                
                CollectionStatusCard(
                    collections: collections,
                    onRefresh: { collectionsInfo = listCollections(collections) }
                )
                .padding()
                
                Spacer()
            }
            .tabItem {
                Label("Overview", systemImage: "gauge")
            }
            .tag(0)
            
            // MARK: - Vector Operations Tab
            VStack {
                VectorCard(
                    title: "Input Vectors",
                    vectors: [
                        ("Vector A", $vectorA),
                        ("Vector B", $vectorB)
                    ]
                )
                .padding()
                .onChange(of: vectorA) { _, _ in
                    updateVectorOperations()
                }
                .onChange(of: vectorB) { _, _ in
                    updateVectorOperations()
                }
                
                VectorOperationsCard(
                    normalizedA: normA,
                    l2Distance: l2,
                    cosineDistance: cosine,
                    innerProduct: innerProd
                )
                .padding()
                
                Spacer()
            }
            .tabItem {
                Label("Vectors", systemImage: "function")
            }
            .tag(1)
            
            // MARK: - Collections Tab
            VStack {
                HStack(spacing: 16) {
                    Button(action: { showCreateCollection = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("New Collection")
                        }
                    }
                    .buttonStyle(ActionButtonStyle(backgroundColor: .blue))
                    
                    Button(action: { showAddDocument = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill.badge.plus")
                            Text("Add Document")
                        }
                    }
                    .buttonStyle(ActionButtonStyle(backgroundColor: .green))
                    
                    Button(action: { showResetDatabase = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.circle.fill")
                            Text("Reset DB")
                        }
                    }
                    .buttonStyle(ActionButtonStyle(backgroundColor: .red))
                }
                .padding(.vertical, 8)
                
                if !collectionsInfo.contains("...") {
                    ScrollView {
                        Text(collectionsInfo)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(10)
                            .padding()
                    }
                }
                
                QueryInterface(
                    collections: collections,
                    queryResults: $queryResults
                )
                .padding()
                
                Spacer()
            }
            .tabItem {
                Label("Collections", systemImage: "folder")
            }
            .tag(2)
            
            // Persistent Storage Tab
            PersistentStorageView()
                .tabItem {
                    Label("Persistent", systemImage: "externaldrive")
                }
                .tag(3)
        }
        .task { @MainActor in
            await runDemo()
        }
        .sheet(isPresented: $showCreateCollection) {
            NavigationStack {
                CreateCollectionView(onCollectionCreated: { name in
                    collections.append(name)
                    collectionsInfo = listCollections(collections)
                })
            }
        }
        .sheet(isPresented: $showResetDatabase) {
            NavigationStack {
                ResetDatabaseView(onReset: {
                    collections.removeAll()
                    collectionsInfo = "..."
                    queryResults = ""
                })
            }
        }
        .sheet(isPresented: $showAddDocument) {
            NavigationStack {
                DocumentManagementView(collections: collections)
            }
        }
    }
    
    @MainActor
    private func runDemo() async {
        // Basic info
        version   = chromaVersion()
        heartbeat = heartbeatTimestampNanos()
        
        // Vector math
        normA     = normalizeVector(v: vectorA)
        l2        = l2Distance(a: vectorA, b: vectorB)
        
        // For cosine distance, normalize both vectors first
        let normalizedA = normalizeVector(v: vectorA)
        let normalizedB = normalizeVector(v: vectorB)
        cosine    = cosineDistance(a: normalizedA, b: normalizedB)
        
        innerProd = innerProductDistance(a: vectorA, b: vectorB)
        
        // Console log for sanity
        print("normalizeVector:", normA)
        print("l2:", l2, "| cosine:", cosine, "| inner product:", innerProd)
    }
    
    @MainActor
    private func updateVectorOperations() {
        // Normalize for correct L2 normalization display
        normA = normalizeVector(v: vectorA)
        
        // Calculate L2 distance (works directly with original vectors)
        l2 = l2Distance(a: vectorA, b: vectorB)
        
        // For cosine distance, normalize both vectors first
        let normalizedA = normalizeVector(v: vectorA)
        let normalizedB = normalizeVector(v: vectorB)
        cosine = cosineDistance(a: normalizedA, b: normalizedB)
        
        // Inner product can use original vectors
        innerProd = innerProductDistance(a: vectorA, b: vectorB)
    }
    
    private func string(_ array: [Float]) -> String {
        "[" + array.map { String(format: "%.3f", $0) }.joined(separator: ", ") + "]"
    }
}

// MARK: - Supporting Views
struct InfoCard: View {
    let title: String
    let content: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            ForEach(content, id: \.0) { item in
                HStack {
                    Text(item.0)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(item.1)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct VectorComponentField: View {
    let index: Int
    let binding: Binding<Float>
    @State private var text: String = ""
    
    var body: some View {
        TextField(
            "Value \(index + 1)",
            text: $text
        )
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 80)
        .onChange(of: text) { _, newValue in
            if let value = Float(newValue) {
                binding.wrappedValue = value
            }
        }
        .onAppear {
            text = String(format: "%.3f", binding.wrappedValue)
        }
    }
}

struct VectorRow: View {
    let label: String
    let vector: Binding<[Float]>
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .foregroundColor(.secondary)
            HStack {
                ForEach(Array(vector.wrappedValue.enumerated()), id: \.offset) { index, _ in
                    VectorComponentField(
                        index: index,
                        binding: vectorBinding(for: index)
                    )
                }
            }
        }
    }
    
    private func vectorBinding(for index: Int) -> Binding<Float> {
        Binding(
            get: { vector.wrappedValue[index] },
            set: { newValue in
                var array = vector.wrappedValue
                array[index] = newValue.isNaN ? 0 : newValue
                vector.wrappedValue = array
            }
        )
    }
}

struct VectorCard: View {
    let title: String
    let vectors: [(String, Binding<[Float]>)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            ForEach(vectors.indices, id: \.self) { index in
                VectorRow(
                    label: vectors[index].0,
                    vector: vectors[index].1
                )
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct VectorOperationsCard: View {
    let normalizedA: [Float]
    let l2Distance: Float
    let cosineDistance: Float
    let innerProduct: Float
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vector Operations")
                .font(.headline)
            
            Group {
                HStack {
                    Text("Normalized A")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatVector(normalizedA))
                }
                
                HStack {
                    Text("L2 Distance")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.3f", l2Distance))
                }
                
                HStack {
                    Text("Cosine Distance")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.3f", cosineDistance))
                }
                
                HStack {
                    Text("Inner Product")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.3f", innerProduct))
                }
            }
            .font(.system(.body, design: .monospaced))
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func formatVector(_ v: [Float]) -> String {
        "[" + v.map { String(format: "%.3f", $0) }.joined(separator: ", ") + "]"
    }
}

struct CollectionStatusCard: View {
    let collections: [String]
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Collections Status")
                    .font(.headline)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            
            HStack {
                Text("Collections")
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(collections.count)")
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Query Interface
struct QueryInterface: View {
    let collections: [String]
    @State private var selectedCollection = ""
    @State private var queryVector: String = "1.0, 0.0, 0.0"
    @State private var numResults: String = "5"
    @Binding var queryResults: String
    @State private var showingDocuments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showingDocuments {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Similarity Search")
                        .font(.headline)
                    
                    // Collection Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Collection")
                            .fontWeight(.medium)
                        HStack {
                            Picker("Collection", selection: $selectedCollection) {
                                Text("Select Collection").tag("")
                                ForEach(collections, id: \.self) { collection in
                                    Text(collection).tag(collection)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            if !selectedCollection.isEmpty {
                                Button("View Documents") {
                                    showingDocuments = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    
                    if !selectedCollection.isEmpty {
                        // Search Vector Input
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
                            runSearch()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        if !queryResults.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Search Results")
                                    .font(.headline)
                                    .padding(.top)
                                
                                ScrollView {
                                    Text(queryResults)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 200)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingDocuments) {
            CollectionDocumentsView(collectionName: selectedCollection)
        }
    }
    
    private func runSearch() {
        let vectorComponents = queryVector.split(separator: ",").compactMap {
            Float($0.trimmingCharacters(in: .whitespaces))
        }
        
        guard !vectorComponents.isEmpty else {
            queryResults = "Invalid vector format"
            return
        }
        
        guard let numResultsInt = UInt32(numResults) else {
            queryResults = "Invalid number of results"
            return
        }
        
        let results = queryCollection(
            collectionName: selectedCollection,
            queryEmbedding: vectorComponents,
            nResults: numResultsInt,
            includeMetadata: true
        )
        
        queryResults = formatQueryResults(results)
    }
}

// MARK: - Collection Documents View
struct CollectionDocumentsView: View {
    let collectionName: String
    @State private var documents: [DocumentItem] = []
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss
    
    struct DocumentItem: Identifiable {
        let id: String
        let content: String
        let metadata: [String: String]
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Documents in \(collectionName)")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            
            if isLoading {
                ProgressView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(documents) { doc in
                            DocumentRow(document: doc)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            loadDocuments()
        }
    }
    
    private func loadDocuments() {
        isLoading = true
        let result = queryCollection(
            collectionName: collectionName,
            queryEmbedding: [1.0, 0.0, 0.0],
            nResults: 1000,
            includeMetadata: true
        )
        
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ids = json["ids"] as? [String],
           let metadatas = json["metadatas"] as? [[String: String]] {
            
            documents = zip(ids, metadatas).map { id, metadata in
                DocumentItem(
                    id: id,
                    content: metadata["content"] ?? "",
                    metadata: metadata
                )
            }.sorted { $0.id < $1.id }
        }
        
        isLoading = false
    }
}

// MARK: - Document Row
struct DocumentRow: View {
    let document: CollectionDocumentsView.DocumentItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(document.id)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let timestamp = Double(document.metadata["created_at"] ?? ""),
                   let date = timestamp.formatAsDate() {
                    Text(date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(document.content)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// Helper extension for date formatting
extension Double {
    func formatAsDate() -> String? {
        let date = Date(timeIntervalSince1970: self)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Custom button style
struct ActionButtonStyle: ButtonStyle {
    let backgroundColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: backgroundColor.opacity(0.3), radius: 5, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

// MARK: - Create Collection View
struct CreateCollectionView: View {
    @State private var collectionName = ""
    @State private var description = ""
    
    var onCollectionCreated: (String) -> Void
    
    @State private var isCreated = false
    @State private var showingResult = false
    @State private var errorMessage = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Create Collection")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Collection Details Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Collection Details")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Collection Name")
                                .fontWeight(.medium)
                            TextField("Enter collection name", text: $collectionName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .fontWeight(.medium)
                            TextField("Describe your collection", text: $description)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding()
                    .cornerRadius(12)
                    
                    // Result Section
                    if showingResult {
                        ResultSection(
                            isSuccess: isCreated,
                            errorMessage: errorMessage
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Bottom Actions
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Create Collection") {
                    createNewCollection()
                }
                .buttonStyle(ActionButtonStyle(backgroundColor: .blue))
                .disabled(collectionName.isEmpty)
            }
            .padding()
        }
        .onChange(of: isCreated) { _, newValue in
            if newValue {
                onCollectionCreated(collectionName)
                // Delay dismissal to show success state
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
    
    private func createNewCollection() {
        var metadata: [String: String] = [:]
        
        if !description.isEmpty {
            metadata["description"] = description
        }
        
        metadata["created_at"] = "\(Date().timeIntervalSince1970)"
        
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: metadata)
        } catch {
            showingResult = true
            isCreated = false
            errorMessage = "Failed to serialize metadata: \(error.localizedDescription)"
            return
        }
        
        let metadataString = String(data: jsonData, encoding: .utf8)
        let success = createCollection(name: collectionName, metadataJson: metadataString)
        
        showingResult = true
        isCreated = success
        errorMessage = success ? "" : "Collection may already exist or name is invalid"
    }
}

// MARK: - Reset Database View
struct ResetDatabaseView: View {
    @State private var isReset = false
    @Environment(\.dismiss) private var dismiss
    var onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("⚠️ Warning ⚠️")
                .font(.title)
                .fontWeight(.bold)
            
            Text("This will delete all collections and data in the database.\nThis action cannot be undone.")
                .multilineTextAlignment(.center)
            
            if isReset {
                Label("Database has been reset", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            Button("Reset Database") {
                let success = resetDatabase()
                isReset = success
                if success {
                    onReset()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding()
            
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Reset Database")
    }
}

// MARK: - Document Management View
private struct DocumentHeaderView: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.title2)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
    }
}

private struct EmptyCollectionsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Create a collection first")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DocumentDetailsSection: View {
    let collections: [String]
    @Binding var collectionName: String
    @Binding var documentId: String
    @Binding var content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Document Details")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Collection")
                    .fontWeight(.medium)
                Picker("Collection", selection: $collectionName) {
                    Text("Select Collection").tag("")
                    ForEach(collections, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .padding(8)
                .cornerRadius(8)
            }
            
            FormField(
                label: "Document ID",
                placeholder: "Enter document ID",
                text: $documentId
            )
            
            ContentEditor(content: $content)
        }
        .padding()
        .cornerRadius(12)
    }
}

private struct EmbeddingOptionsSection: View {
    @Binding var useCustomEmbedding: Bool
    @Binding var embeddingText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Embedding Options")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Toggle("Use Custom Embedding", isOn: $useCustomEmbedding)
                .padding(.vertical, 4)
            
            if useCustomEmbedding {
                FormField(
                    label: "Embedding Vector",
                    placeholder: "Enter comma-separated values",
                    text: $embeddingText,
                    isMonospaced: true
                )
            } else {
                Text("A default embedding will be used")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
        }
        .padding()
        .cornerRadius(12)
    }
}

private struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isMonospaced: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .fontWeight(.medium)
            TextField(placeholder, text: $text)
                .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ContentEditor: View {
    @Binding var content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .fontWeight(.medium)
            TextEditor(text: $content)
                .frame(height: 120)
                .padding(4)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Group {
                        if content.isEmpty {
                            Text("Enter document content...")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
    }
}

private struct ResultSection: View {
    let isSuccess: Bool
    let errorMessage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isSuccess {
                Label("Operation completed successfully", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Label("Operation failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cornerRadius(12)
    }
}

private struct BottomActionBar: View {
    let primaryAction: () -> Void
    let primaryLabel: String
    let isDisabled: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Button("Cancel", action: onDismiss)
                .buttonStyle(.bordered)
            
            Button(action: primaryAction) {
                Text(primaryLabel)
            }
            .buttonStyle(ActionButtonStyle(backgroundColor: .blue))
            .disabled(isDisabled)
        }
        .padding()
    }
}

// MARK: - Document Management View
struct DocumentManagementView: View {
    @State private var collectionName = ""
    @State private var documentId = ""
    @State private var content = ""
    @State private var useCustomEmbedding = false
    @State private var embeddingText = "0.1, 0.2, 0.3, 0.4, 0.5"
    
    @State private var isSuccess = false
    @State private var showResult = false
    @State private var errorMessage = ""
    
    let collections: [String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            DocumentHeaderView(title: "Add Document")
            
            if collections.isEmpty {
                EmptyCollectionsView()
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        DocumentDetailsSection(
                            collections: collections,
                            collectionName: $collectionName,
                            documentId: $documentId,
                            content: $content
                        )
                        
                        EmbeddingOptionsSection(
                            useCustomEmbedding: $useCustomEmbedding,
                            embeddingText: $embeddingText
                        )
                        
                        if showResult {
                            ResultSection(
                                isSuccess: isSuccess,
                                errorMessage: errorMessage
                            )
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            BottomActionBar(
                primaryAction: addDocumentToCollection,
                primaryLabel: "Add Document",
                isDisabled: collectionName.isEmpty || documentId.isEmpty || content.isEmpty,
                onDismiss: { dismiss() }
            )
        }
        .onChange(of: isSuccess) { _, success in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
    
    private func addDocumentToCollection() {
        // Validate basic requirements
        guard !collectionName.isEmpty, !documentId.isEmpty, !content.isEmpty else {
            showResult = true
            isSuccess = false
            errorMessage = "Collection name, document ID and content are required"
            return
        }
        
        // Verify collection exists
        let collections = listCollections([collectionName])
        guard collections.contains(collectionName) else {
            showResult = true
            isSuccess = false
            errorMessage = "Collection '\(collectionName)' does not exist"
            return
        }
        
        // Parse embedding if custom is enabled
        let embedding: [Float]?
        if useCustomEmbedding {
            embedding = embeddingText
                .split(separator: ",")
                .compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
            
            if embedding?.isEmpty ?? true {
                showResult = true
                isSuccess = false
                errorMessage = "Invalid embedding format"
                return
            }
            
            // TODO: Add dimension validation once we have access to collection metadata
            // if embedding?.count != expectedDimension { ... }
        } else {
            // For now, use a default embedding
            // TODO: Implement proper text-to-embedding conversion
            embedding = Array(repeating: Float(0), count: 5)
        }
        
        // Create metadata with proper type handling
        var metadata: [String: String] = [:]
        
        metadata["content"] = content
        metadata["created_at"] = "\(Date().timeIntervalSince1970)"
        
        // Convert to JSON with error handling
        let metadataJson: String?
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: metadata)
            metadataJson = String(data: jsonData, encoding: .utf8)
        } catch {
            showResult = true
            isSuccess = false
            errorMessage = "Failed to serialize metadata: \(error.localizedDescription)"
            return
        }
        
        // Add document with proper error handling
        let success = addDocument(
            collectionName: collectionName,
            documentId: documentId,
            content: content,
            embedding: embedding,
            metadataJson: metadataJson
        )
        
        showResult = true
        isSuccess = success
        
        if !success {
            errorMessage = """
                Failed to add document. Possible reasons:
                - Document ID already exists
                - Invalid embedding dimensions
                - Collection was deleted
                Please check the logs for more details.
                """
        }
        
        // Log for debugging
        print("[Document Addition] Collection: \(collectionName)")
        print("[Document Addition] Document ID: \(documentId)")
        print("[Document Addition] Content length: \(content.count)")
        print("[Document Addition] Embedding size: \(embedding?.count ?? 0)")
        print("[Document Addition] Success: \(success)")
    }
}

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
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .opacity(collectionName.isEmpty ? 0.7 : 1.0)
                
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
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
