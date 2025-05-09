import SwiftUI
import Chroma

struct SearchDebugView: View {
    @State private var results = "No results yet"
    
    var body: some View {
        VStack {
            Text("Vector Search Debug")
                .font(.headline)
            
            Button("Run Basic Tests") {
                runTests()
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            ScrollView {
                Text(results)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding()
        }
        .padding()
    }
    
    private func runTests() {
        var output = "Starting search diagnostics...\n\n"
        
        // Test 1: Check if the collection exists
        let collectionName = "first"
        output += "Test 1: Checking if collection '\(collectionName)' exists\n"
        let exists = persistentCollectionExists(collectionName: collectionName) == 1
        output += "Collection exists: \(exists)\n\n"
        
        if !exists {
            results = output + "Collection doesn't exist. Tests stopped."
            return
        }
        
        // Test 2: Check embedding dimension
        output += "Test 2: Checking embedding dimension\n"
        let dimension = embeddingDimension(collectionName: collectionName)
        output += "Reported dimension: \(dimension)\n\n"
        
        // Test 3: Create two different random vectors
        output += "Test 3: Testing with random vectors\n"
        let randomVector1 = randomVector(len: dimension)
        let randomVector2 = randomVector(len: dimension)
        
        // Calculate distance between them to verify they're different
        let distance = l2Distance(a: randomVector1, b: randomVector2)
        output += "Distance between random vectors: \(distance)\n\n"
        
        // Test 4: Try search with first random vector
        output += "Test 4: Search with first random vector\n"
        let searchResult1 = queryPersistentCollection(
            collectionName: collectionName,
            queryEmbedding: randomVector1,
            nResults: 5,
            includeMetadata: true
        )
        output += "Raw result: \(searchResult1)\n\n"
        
        // Test 5: Try search with second random vector
        output += "Test 5: Search with second random vector\n"
        let searchResult2 = queryPersistentCollection(
            collectionName: collectionName,
            queryEmbedding: randomVector2,
            nResults: 5,
            includeMetadata: true
        )
        output += "Raw result: \(searchResult2)\n\n"
        
        // Test 6: Try to directly add a new embedding and then search for it
        output += "Test 6: Add new embedding and search for it\n"
        
        // Create random vector as our new embedding
        let testVector = randomVector(len: dimension)
        let testId = "test_\(Int(Date().timeIntervalSince1970))"
        
        // Test adding the embedding
        let addResult = addPersistentEmbeddings(
            collectionName: collectionName,
            ids: [testId],
            embeddings: [testVector],
            metadatas: ["{\"content\": \"Test document\"}"]
        )
        
        output += "Add embedding result: \(addResult)\n"
        
        if addResult > 0 {
            // Now immediately search for this exact vector
            let exactSearchResult = queryPersistentCollection(
                collectionName: collectionName,
                queryEmbedding: testVector,
                nResults: 1,
                includeMetadata: true
            )
            
            output += "Search for exact same vector result: \(exactSearchResult)\n\n"
        } else {
            output += "Failed to add test embedding\n\n"
        }
        
        // Test 7: Try with a zero vector
        output += "Test 7: Search with zero vector\n"
        let zeroVec = zeroVector(len: dimension)
        let zeroResult = queryPersistentCollection(
            collectionName: collectionName,
            queryEmbedding: zeroVec,
            nResults: 5,
            includeMetadata: true
        )
        output += "Zero vector search result: \(zeroResult)\n\n"
        
        // Test 8: Check if any vectors exist at all
        output += "Test 8: Inspect collection\n"
        let docCount = countDocuments(collectionName: collectionName)
        output += "Document count: \(docCount)\n"
        output += "Collection metadata: \(getCollectionMetadata(name: collectionName))\n\n"
        
        output += "All tests completed."
        results = output
    }
}

#Preview {
    SearchDebugView()
}
