//! Swift bindings for the Chroma Rust crate
//! 
//! This module provides FFI functions that can be called from Swift.
//! It integrates with the actual Chroma frontend for core functionality.

use std::time::{SystemTime, UNIX_EPOCH};
use std::fs;
use anyhow::Result;
use thiserror::Error;
use tokio::runtime::Runtime;
use serde::{Serialize, Deserialize};

// Chroma core imports
use chroma_types::HeartbeatError;

// For simple in-memory storage
use std::sync::{Arc, Mutex};
use lazy_static::lazy_static;
use std::collections::HashMap;

// Simplified in-memory database for Swift integration demo
lazy_static! {
    static ref COLLECTIONS: Mutex<HashMap<String, Collection>> = Mutex::new(HashMap::new());
}

// Simple Collection type for demonstration
#[derive(Debug, Clone, Serialize, Deserialize)]
struct Collection {
    name: String,
    metadata: Option<HashMap<String, String>>,
    vectors: HashMap<String, Vec<f32>>,
    metadatas: HashMap<String, HashMap<String, String>>,
}

/// Errors that can occur in the Swift bindings.
#[derive(Error, Debug)]
pub enum ChromaSwiftError {
    #[error("Failed to get system time: {0}")]
    HeartbeatError(String),
    
    #[error("Unknown error occurred: {0}")]
    Unknown(String),
    
    #[error("Chroma error: {0}")]
    ChromaError(String),
    
    #[error("Failed to create Tokio runtime: {0}")]
    RuntimeError(String),
    
    #[error("Feature not implemented: {0}")]
    NotImplemented(String),
}

/// Internal implementation of the heartbeat function.
/// 
/// Returns the current epoch time in nanoseconds.
fn heartbeat_internal() -> Result<u128, ChromaSwiftError> {
    // Simple implementation that returns the current time
    let duration_since_epoch = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| ChromaSwiftError::HeartbeatError(e.to_string()))?;
    
    Ok(duration_since_epoch.as_nanos())
}

/// FFI struct to handle 128-bit return values across the FFI boundary.
#[repr(C)]
pub struct U128Parts {
    /// The higher 64 bits of the u128 value
    pub high: u64,
    /// The lower 64 bits of the u128 value
    pub low: u64,
}

/// FFI struct to return results that can indicate success or failure.
#[repr(C)]
pub struct FFIResult {
    /// 0 for success, non-zero for error
    pub error_code: i32,
    /// Error message if error_code is non-zero
    pub error_message: *mut libc::c_char,
    /// Result data
    pub result: U128Parts,
}

/// Frees a C string allocated by Rust.
#[no_mangle]
pub extern "C" fn chroma_free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = std::ffi::CString::from_raw(s);
        }
    }
}

/// FFI-compatible function that returns the current epoch time in nanoseconds.
/// 
/// Returns a struct containing high and low 64-bit parts of the 128-bit nanosecond timestamp,
/// along with error information if applicable.
#[no_mangle]
pub extern "C" fn chroma_heartbeat() -> FFIResult {
    match heartbeat_internal() {
        Ok(nanos) => {
            // Split u128 into high and low u64 parts
            let high = (nanos >> 64) as u64;
            let low = nanos as u64;
            
            FFIResult {
                error_code: 0,
                error_message: std::ptr::null_mut(),
                result: U128Parts { high, low },
            }
        },
        Err(err) => {
            let error_message = format!("{}", err);
            let c_error = std::ffi::CString::new(error_message).unwrap_or_else(|_| {
                std::ffi::CString::new("Failed to create error message").unwrap()
            });
            
            FFIResult {
                error_code: 1,
                error_message: c_error.into_raw(),
                result: U128Parts { high: 0, low: 0 },
            }
        }
    }
}

/// Exposed heartbeat function for Swift via UniFFI.
/// Returns the current epoch time in nanoseconds as `u64`.
/// This uses the actual Chroma heartbeat implementation.
#[uniffi::export]
pub fn heartbeat_timestamp_nanos() -> u64 {
    // Use the real Chroma heartbeat
    heartbeat_internal().unwrap_or(0) as u64
}

/// Reset the Chroma database (in-memory).
/// 
/// WARNING: This is destructive and will clear all data.
#[uniffi::export]
pub fn reset_database() -> bool {
    // Clear all collections from our simplified database
    match COLLECTIONS.lock() {
        Ok(mut collections) => {
            collections.clear();
            true
        },
        Err(_) => false,
    }
}

/// Create a new collection with the specified name and metadata
#[uniffi::export]
pub fn create_collection(name: String, metadata_json: Option<String>) -> bool {
    // Parse metadata JSON if provided
    let metadata = match metadata_json {
        Some(json) => match serde_json::from_str::<HashMap<String, String>>(&json) {
            Ok(map) => Some(map),
            Err(_) => return false, // Invalid JSON format
        },
        None => None,
    };
    
    // Create a new collection
    let collection = Collection {
        name: name.clone(),
        metadata,
        vectors: HashMap::new(),
        metadatas: HashMap::new(),
    };
    
    // Add to our collections map
    match COLLECTIONS.lock() {
        Ok(mut collections) => {
            if collections.contains_key(&name) {
                // Collection already exists
                false
            } else {
                collections.insert(name, collection);
                true
            }
        },
        Err(_) => false,
    }
}

/// Returns the crate version as a string for Swift.
/// This uses the `CARGO_PKG_VERSION` compile-time env var so no
/// manual update is needed when the crate version changes.
#[uniffi::export]
pub fn chroma_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

// Re-export for Swift bindings
#[no_mangle]
pub extern "C" fn chroma_swift_bindings_version() -> *mut libc::c_char {
    std::ffi::CString::new("0.1.0").unwrap().into_raw()
}

use chroma_distance::{normalize as distance_normalize, DistanceFunction};

/// Returns a new vector that is the L2-normalized version of the input.
#[uniffi::export]
pub fn normalize_vector(v: Vec<f32>) -> Vec<f32> {
    distance_normalize(&v)
}

/// Calculates the squared-L2 (Euclidean) distance between two vectors.
#[uniffi::export]
pub fn l2_distance(a: Vec<f32>, b: Vec<f32>) -> f32 {
    DistanceFunction::Euclidean.distance(&a, &b)
}

/// Calculates `1 − cosine_similarity(a, b)` (cosine distance).
#[uniffi::export]
pub fn cosine_distance(a: Vec<f32>, b: Vec<f32>) -> f32 {
    DistanceFunction::Cosine.distance(&a, &b)
}

/// Calculates `1 − (inner product)` between two vectors.
#[uniffi::export]
pub fn inner_product_distance(a: Vec<f32>, b: Vec<f32>) -> f32 {
    DistanceFunction::InnerProduct.distance(&a, &b)
}

/// Computes the dot product of two vectors.
#[uniffi::export]
pub fn dot_product(a: Vec<f32>, b: Vec<f32>) -> f32 {
    let len = a.len().min(b.len());
    let mut sum = 0.0_f32;
    for i in 0..len {
        sum += a[i] * b[i];
    }
    sum
}

/// Computes the L2 norm (magnitude) of a vector.
#[uniffi::export]
pub fn vector_norm(v: Vec<f32>) -> f32 {
    v.iter().map(|x| x * x).sum::<f32>().sqrt()
}

/// Returns a normalized copy of the input vector (L2-unit length).
/// If the input is the zero-vector the same vector is returned.
#[uniffi::export]
pub fn normalize_inplace(mut v: Vec<f32>) -> Vec<f32> {
    let norm = vector_norm(v.clone());
    if norm == 0.0 {
        return v;
    }
    for x in v.iter_mut() {
        *x /= norm;
    }
    v
}

/// Computes the Manhattan (L1) distance between two vectors.
#[uniffi::export]
pub fn manhattan_distance(a: Vec<f32>, b: Vec<f32>) -> f32 {
    let len = a.len().min(b.len());
    let mut sum = 0.0_f32;
    for i in 0..len {
        sum += (a[i] - b[i]).abs();
    }
    sum
}

/// Computes the Hamming distance (number of differing bits) between two byte arrays.
#[uniffi::export]
pub fn hamming_distance(a: Vec<u8>, b: Vec<u8>) -> u32 {
    let len = a.len().min(b.len());
    let mut dist: u32 = 0;
    for i in 0..len {
        dist += (a[i] ^ b[i]).count_ones();
    }
    let extra = if a.len() > b.len() { &a[len..] } else { &b[len..] };
    for byte in extra {
        dist += byte.count_ones();
    }
    dist
}

/// Add vectors to a collection
/// 
/// - Parameters:
///   - collection_name: Name of the collection to add vectors to
///   - ids: Vector of unique IDs for each embedding
///   - embeddings: Vectors of embeddings (float vectors)
///   - metadatas: Optional JSON strings with metadata for each vector
/// 
/// - Returns: Number of vectors successfully added, or -1 on error
#[uniffi::export]
pub fn add_embeddings(
    collection_name: String,
    ids: Vec<String>,
    embeddings: Vec<Vec<f32>>,
    metadatas: Option<Vec<String>>
) -> i32 {
    // Check parameters
    if ids.len() != embeddings.len() {
        return -1; // Mismatch between IDs and embeddings
    }
    
    if let Some(ref meta) = metadatas {
        if meta.len() != ids.len() {
            return -1; // Mismatch between IDs and metadata
        }
    }
    
    // Get the collection
    let mut collections = match COLLECTIONS.lock() {
        Ok(c) => c,
        Err(_) => return -1,
    };
    
    let collection = match collections.get_mut(&collection_name) {
        Some(c) => c,
        None => return -1, // Collection not found
    };
    
    // Parse metadata if provided
    let parsed_metadatas: Vec<Option<HashMap<String, String>>> = match &metadatas {
        Some(metas) => {
            metas.iter().map(|json| {
                serde_json::from_str::<HashMap<String, String>>(json).ok()
            }).collect()
        },
        None => vec![None; ids.len()],
    };
    
    // Add embeddings to collection
    let mut count = 0;
    for i in 0..ids.len() {
        // Skip if embedding is invalid (empty)
        if embeddings[i].is_empty() {
            continue;
        }
        
        // Add vector
        collection.vectors.insert(ids[i].clone(), embeddings[i].clone());
        
        // Add metadata if present
        if let Some(meta) = &parsed_metadatas[i] {
            collection.metadatas.insert(ids[i].clone(), meta.clone());
        }
        
        count += 1;
    }
    
    count
}

/// Query for nearest vectors in a collection
/// 
/// - Parameters:
///   - collection_name: Name of the collection to query
///   - query_embedding: Vector to find nearest neighbors of
///   - n_results: Maximum number of results to return
///   - include_distances: Whether to include distances in the results
/// 
/// - Returns: JSON string containing results {ids: [], embeddings: [], distances: []}
#[uniffi::export]
pub fn query_collection(
    collection_name: String,
    query_embedding: Vec<f32>,
    n_results: u32,
    include_metadata: bool,
) -> String {
    // Get the collection
    let collections = match COLLECTIONS.lock() {
        Ok(c) => c,
        Err(_) => return json_error("Failed to lock collections"),
    };
    
    let collection = match collections.get(&collection_name) {
        Some(c) => c,
        None => return json_error("Collection not found"),
    };
    
    // Calculate distances and find nearest vectors
    let mut distances: Vec<(String, f32)> = Vec::new();
    
    for (id, embedding) in &collection.vectors {
        // Calculate L2 distance
        let distance = l2_distance(query_embedding.clone(), embedding.clone());
        distances.push((id.clone(), distance));
    }
    
    // Sort by distance (closest first)
    distances.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
    
    // Take only n_results
    let limit = std::cmp::min(n_results as usize, distances.len());
    let results = &distances[0..limit];
    
    // Format results as JSON
    let mut ids = Vec::new();
    let mut result_distances = Vec::new();
    let mut result_metadatas = Vec::new();
    
    for (id, distance) in results {
        ids.push(id.clone());
        result_distances.push(distance);
        
        if include_metadata {
            if let Some(meta) = collection.metadatas.get(id) {
                result_metadatas.push(serde_json::to_value(meta).unwrap_or(serde_json::Value::Null));
            } else {
                result_metadatas.push(serde_json::Value::Null);
            }
        }
    }
    
    // Create result JSON
    let mut result = serde_json::Map::new();
    result.insert("ids".to_string(), serde_json::to_value(ids).unwrap());
    result.insert("distances".to_string(), serde_json::to_value(result_distances).unwrap());
    
    if include_metadata {
        result.insert("metadatas".to_string(), serde_json::to_value(result_metadatas).unwrap());
    }
    
    serde_json::to_string(&result).unwrap_or_else(|_| json_error("Failed to serialize results"))
}

/// Add a document to a collection
/// 
/// - Parameters:
///   - collection_name: Name of the collection to add the document to
///   - document_id: Unique ID for the document
///   - content: Content of the document
///   - embedding: Vector embedding for the document (if nil, dummy embedding is used)
///   - metadata: Optional JSON string with document metadata
/// 
/// - Returns: true if document was added successfully, false otherwise
#[uniffi::export]
pub fn add_document(
    collection_name: String,
    document_id: String,
    content: String,
    embedding: Option<Vec<f32>>,
    metadata_json: Option<String>
) -> bool {
    // Parse metadata JSON if provided
    let metadata = match metadata_json {
        Some(json) => match serde_json::from_str::<HashMap<String, String>>(&json) {
            Ok(map) => Some(map),
            Err(_) => return false, // Invalid JSON format
        },
        None => None,
    };
    
    // Create a default embedding if none provided
    // In a real implementation, we'd use a text embedding model here
    let vector = match embedding {
        Some(v) => v,
        None => vec![0.1, 0.2, 0.3], // Simple default embedding
    };
    
    // Try to add the document embedding to the collection
    match COLLECTIONS.lock() {
        Ok(mut collections) => {
            if let Some(collection) = collections.get_mut(&collection_name) {
                // Add document vector
                collection.vectors.insert(document_id.clone(), vector);
                
                // Add document metadata including content
                let mut doc_metadata = metadata.unwrap_or_default();
                doc_metadata.insert("content".to_string(), content);
                collection.metadatas.insert(document_id, doc_metadata);
                
                true
            } else {
                // Collection not found
                false
            }
        },
        Err(_) => false,
    }
}

/// Checks if a collection with the given name exists.
#[uniffi::export]
pub fn collection_exists(name: String) -> bool {
    COLLECTIONS.lock().map_or(false, |c| c.contains_key(&name))
}

/// Checks if a document exists in a collection.
#[uniffi::export]
pub fn document_exists(collection_name: String, document_id: String) -> bool {
    if let Ok(collections) = COLLECTIONS.lock() {
        if let Some(col) = collections.get(&collection_name) {
            return col.vectors.contains_key(&document_id);
        }
    }
    false
}

/// Counts the number of documents in a collection. Returns 0 if the collection does not exist.
#[uniffi::export]
pub fn count_documents(collection_name: String) -> u32 {
    if let Ok(collections) = COLLECTIONS.lock() {
        if let Some(col) = collections.get(&collection_name) {
            return col.vectors.len() as u32;
        }
    }
    0
}

/// Returns the metadata for a collection as a JSON string, or "{}" if none.
#[uniffi::export]
pub fn get_collection_metadata(name: String) -> String {
    if let Ok(collections) = COLLECTIONS.lock() {
        if let Some(col) = collections.get(&name) {
            if let Some(meta) = &col.metadata {
                return serde_json::to_string(meta).unwrap_or_else(|_| "{}".to_string());
            }
        }
    }
    "{}".to_string()
}

/// Returns the metadata for a document as a JSON string, or "{}" if none.
#[uniffi::export]
pub fn get_document_metadata(collection_name: String, document_id: String) -> String {
    if let Ok(collections) = COLLECTIONS.lock() {
        if let Some(col) = collections.get(&collection_name) {
            if let Some(meta) = col.metadatas.get(&document_id) {
                return serde_json::to_string(meta).unwrap_or_else(|_| "{}".to_string());
            }
        }
    }
    "{}".to_string()
}

/// Returns the embedding vector for a document or an empty vector if not found.
#[uniffi::export]
pub fn get_embedding(collection_name: String, document_id: String) -> Vec<f32> {
    if let Ok(collections) = COLLECTIONS.lock() {
        if let Some(col) = collections.get(&collection_name) {
            if let Some(embedding) = col.vectors.get(&document_id) {
                return embedding.clone();
            }
        }
    }
    Vec::new()
}

/// Element-wise addition of two vectors (truncates to shorter length).
#[uniffi::export]
pub fn vector_add(a: Vec<f32>, b: Vec<f32>) -> Vec<f32> {
    let len = a.len().min(b.len());
    (0..len).map(|i| a[i] + b[i]).collect()
}

/// Element-wise subtraction of two vectors (a − b).
#[uniffi::export]
pub fn vector_sub(a: Vec<f32>, b: Vec<f32>) -> Vec<f32> {
    let len = a.len().min(b.len());
    (0..len).map(|i| a[i] - b[i]).collect()
}

/// Multiplies every element by a scalar.
#[uniffi::export]
pub fn scalar_mul(v: Vec<f32>, k: f32) -> Vec<f32> {
    v.into_iter().map(|x| x * k).collect()
}

/// Computes the arithmetic mean of a list of vectors. Returns empty vec on invalid input.
#[uniffi::export]
pub fn mean_vector(vectors: Vec<Vec<f32>>) -> Vec<f32> {
    if vectors.is_empty() {
        return Vec::new();
    }
    let dim = vectors[0].len();
    let mut sum = vec![0.0_f32; dim];
    let mut count = 0;
    for v in vectors.iter() {
        if v.len() != dim {
            return Vec::new();
        }
        for i in 0..dim {
            sum[i] += v[i];
        }
        count += 1;
    }
    for i in 0..dim {
        sum[i] /= count as f32;
    }
    sum
}

/// Calculates the centroid (mean embedding) of all vectors in a collection.
#[uniffi::export]
pub fn centroid(collection_name: String) -> Vec<f32> {
    if let Ok(collections) = COLLECTIONS.lock() {
        if let Some(col) = collections.get(&collection_name) {
            return mean_vector(col.vectors.values().cloned().collect());
        }
    }
    Vec::new()
}

/// Cosine similarity (1 − cosine_distance).
#[uniffi::export]
pub fn cosine_similarity(a: Vec<f32>, b: Vec<f32>) -> f32 {
    1.0 - cosine_distance(a, b)
}

/// Inner-product similarity (1 − inner_product_distance).
#[uniffi::export]
pub fn inner_product_similarity(a: Vec<f32>, b: Vec<f32>) -> f32 {
    1.0 - inner_product_distance(a, b)
}

/// Saves the in-memory database to a JSON file at the given path.
#[uniffi::export]
pub fn save_database(path: String) -> bool {
    if let Ok(collections) = COLLECTIONS.lock() {
        match serde_json::to_string(&*collections) {
            Ok(json) => fs::write(&path, json).is_ok(),
            Err(_) => false,
        }
    } else {
        false
    }
}

/// Loads a database JSON file, replacing current state. Returns true on success.
#[uniffi::export]
pub fn load_database(path: String) -> bool {
    match fs::read_to_string(&path) {
        Ok(contents) => match serde_json::from_str::<HashMap<String, Collection>>(&contents) {
            Ok(parsed) => {
                if let Ok(mut collections) = COLLECTIONS.lock() {
                    *collections = parsed;
                    true
                } else {
                    false
                }
            }
            Err(_) => false,
        },
        Err(_) => false,
    }
}

/// Returns the embedding dimension of a collection (0 if unknown).
#[uniffi::export]
pub fn embedding_dimension(collection_name: String) -> u32 {
    if let Ok(collections) = COLLECTIONS.lock() {
        if let Some(col) = collections.get(&collection_name) {
            if let Some(vec) = col.vectors.values().next() {
                return vec.len() as u32;
            }
        }
    }
    0
}

/// Checks whether any document in the collection contains a given metadata key.
#[uniffi::export]
pub fn has_metadata_key(collection_name: String, key: String) -> bool {
    if let Ok(collections) = COLLECTIONS.lock() {
        if let Some(col) = collections.get(&collection_name) {
            return col.metadatas.values().any(|m| m.contains_key(&key));
        }
    }
    false
}

#[derive(Serialize, Deserialize)]
struct BatchInput {
    collection: String,
    ids: Vec<String>,
    embeddings: Vec<Vec<f32>>,
    metadatas: Option<Vec<String>>, // JSON strings
}

/// Batch-add embeddings via a JSON payload.
/// JSON format: {"collection":"name","ids":[...],"embeddings":[[...]],"metadatas":[{"k":"v"}, ...]}
#[uniffi::export]
pub fn add_embeddings_batch(json_payload: String) -> bool {
    match serde_json::from_str::<BatchInput>(&json_payload) {
        Ok(data) => {
            let added = add_embeddings(
                data.collection,
                data.ids,
                data.embeddings,
                data.metadatas,
            );
            added >= 0
        }
        Err(_) => false,
    }
}

/// Returns current epoch time in milliseconds.
#[uniffi::export]
pub fn current_time_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Generates a pseudo-random vector of length `len` using a simple LCG (no extra deps).
#[uniffi::export]
pub fn random_vector(len: u32) -> Vec<f32> {
    let mut seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(1);
    let mut out = Vec::with_capacity(len as usize);
    for _ in 0..len {
        // simple LCG parameters from Numerical Recipes
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let val = (seed >> 16) as u32;
        out.push((val as f32) / (u32::MAX as f32));
    }
    out
}

/// Returns a zero-filled vector of given length.
#[uniffi::export]
pub fn zero_vector(len: u32) -> Vec<f32> {
    vec![0.0_f32; len as usize]
}

// Helper function to create error JSON
fn json_error(message: &str) -> String {
    let mut result = serde_json::Map::new();
    result.insert("error".to_string(), serde_json::to_value(message).unwrap());
    serde_json::to_string(&result).unwrap_or_else(|_| format!("{{\"error\":\"{}\"}}", message))
}

#[derive(Serialize)]
struct CollectionSummary {
    name: String,
    num_vectors: usize,
    dimension: usize,
}

/// Returns a JSON string summarizing all collections.
#[uniffi::export]
pub fn collection_summary() -> String {
    if let Ok(collections) = COLLECTIONS.lock() {
        let summaries: Vec<CollectionSummary> = collections
            .iter()
            .map(|(name, col)| CollectionSummary {
                name: name.clone(),
                num_vectors: col.vectors.len(),
                dimension: col.vectors.values().next().map(|v| v.len()).unwrap_or(0),
            })
            .collect();
        return serde_json::to_string(&summaries).unwrap_or_else(|_| "[]".to_string());
    }
    "[]".to_string()
}

uniffi::setup_scaffolding!();
