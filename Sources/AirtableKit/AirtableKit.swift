import Combine
import Foundation

/// Client used to manipulate an Airtable base.
///
/// This is the facade of the library, used to create, modify and get records and attachments from an Airtable base.
public final class Airtable {
    
    /// ID of the base manipulated by the client.
    public let baseID: String
    
    /// API key of the user manipulating the base.
    public let apiKey: String
    
    private static let batchLimit: Int = 10
    private static let airtableURL: URL = URL(string: "https://api.airtable.com/v0")!
    private var baseURL: URL { Self.airtableURL.appendingPathComponent(baseID) }
    
    private let requestEncoder: RequestEncoder = RequestEncoder()
    private let responseDecoder: ResponseDecoder = ResponseDecoder()
    private let errorHander: ErrorHandler = ErrorHandler()
    
    /// Initializes the client to work on a base using the specified API key.
    ///
    /// - Parameters:
    ///   - baseID: The ID of the base manipulated by the client.
    ///   - apiKey: The API key of the user manipulating the base.
    public init(baseID: String, apiKey: String) {
        self.baseID = baseID
        self.apiKey = apiKey
    }
    
    // MARK: - Recover records from a table
    
    /// Lists all records in a table.
    ///
    /// - Parameters:
    ///   - tableName: Name of the table to list records from.
    ///   - fields: Only data for fields whose names are in this list will be included in the result. If you don't need every field, you can use this parameter to reduce the amount of data transferred.
    ///   - maxRecords: The maximum total number of records that will be returned in your requests.
    ///   - pageSize: The number of records returned in each request. Must be less than or equal to 100.
    ///   - offset: The starting point for the current page.
    ///
    /// - Returns: Array of `Record`s
    public func list(tableName: String, fields: [String] = [], formula: String? = nil, maxRecords: Int = 100, pageSize: Int = 100, offset: String? = nil) async throws -> [Record] {
        var queryItems: [URLQueryItem] = []
        queryItems.append(contentsOf: fields.map { URLQueryItem(name: "fields[]", value: $0) })
        queryItems.append(URLQueryItem(name: "maxRecords", value: "\(maxRecords)"))
        queryItems.append(URLQueryItem(name: "pageSize", value: "\(pageSize)"))
        if let offset = offset {
            queryItems.append(URLQueryItem(name: "offset", value: offset))
        }
        if let formula = formula {
            queryItems.append(URLQueryItem(name: "filterByFormula", value: formula))
        }
        
        let request = buildRequest(method: "GET", path: tableName, queryItems: queryItems)
        
        var results = [Record]()
        
        // Get the first set of records (up to 100)
        let response = try await performRequest(request, decoder: responseDecoder.decodeRecordsResponse(data:))
        results.append(contentsOf: response.records)
        
        // If there's an offset, start gathering
        if let offset = response.offset {
            let nextResults = try await list(tableName: tableName, fields: fields, maxRecords: maxRecords, pageSize: pageSize, offset: offset)
            results.append(contentsOf: nextResults)
        }
        
        return results
    }
    
    /// Gets a single record in a table.
    ///
    /// - Parameters:
    ///   - tableName: Name of the table where the record is.
    ///   - recordID: The ID of the record to be fetched.
    public func get(tableName: String, recordID: String) async throws -> Record {
        let request = buildRequest(method: "GET", path: "\(tableName)/\(recordID)")
        return try await performRequest(request, decoder: responseDecoder.decodeRecord(data:))
    }
    
    // MARK: - Add records to a table
    
    /// Creates a record on a table.
    ///
    /// - Parameters:
    ///   - tableName: Name of the table where the record is.
    ///   - record: The record to be created. The record should have `id == nil`.
    public func create(tableName: String, record: Record) async throws -> Record {
        let request = buildRequest(
            method: "POST",
            path: tableName,
            payload: requestEncoder.encodeRecord(record, shouldAddID: false)
        )
        
        return try await performRequest(request, decoder: responseDecoder.decodeRecord(data:))
    }
    
    /// Creates multiple records on a table.
    ///
    /// - Parameters:
    ///   - tableName: Name  of the table where the record is.
    ///   - records: The records to be created. All records should have `id == nil`.
    public func create(tableName: String, records: [Record]) async throws -> [Record] {
        let batches = records.chunked(by: Self.batchLimit)
            .map { requestEncoder.encodeRecords($0, shouldAddID: false) }
            .compactMap { buildRequest(method: "POST", path: tableName, payload: $0) }
        
        var results = [Record]()

        for request in batches {
            let response = try await performRequest(request, decoder: self.responseDecoder.decodeRecords(data:))
            results.append(contentsOf: response)
        }
        
        return results
    }
    
    // MARK: - Update records on a table
    
    /// Updates a record.
    ///
    /// If `replacesEntireRecord == false` (the default), only the fields specified by the record are overwritten (like a `PATCH`); else, all fields are
    /// overwritten and fields not present on the record are emptied on Airtable (like a `PUT`).
    ///
    /// - Parameters:
    ///   - tableName: Name of the table where the record is.
    ///   - record: The record to be updated. The `id` property **must not** be `nil`.
    ///   - replacesEntireRecord: Indicates whether the operation should replace the entire record or just updates the appropriate fields
    public func update(tableName: String, record: Record, replacesEntireRecord: Bool = false) async throws -> Record {
        guard let recordID = record.id else {
            throw AirtableError.invalidParameters(operation: #function, parameters: [tableName, record])
        }
        
        let request = buildRequest(
            method: replacesEntireRecord ? "PUT" : "PATCH",
            path: "\(tableName)/\(recordID)",
            payload: requestEncoder.encodeRecord(record, shouldAddID: false)
        )
        
        return try await performRequest(request, decoder: responseDecoder.decodeRecord(data:))
    }
    
    /// Updates multiple records.
    ///
    /// If `replacesEntireRecord == false` (the default), only the fields specified by each record is overwritten (like a `PATCH`); else, all fields are
    /// overwritten and fields not present on each record is emptied on Airtable (like a `PUT`).
    ///
    /// - Parameters:
    ///   - tableName: Name of the table where the record is.
    ///   - records: The records to be updated.
    ///   - replacesEntireRecord: Indicates whether the operation should replace the entire record or just update the appropriate fields.
    public func update(tableName: String, records: [Record], replacesEntireRecords: Bool = false) async throws -> [Record] {
        let method = replacesEntireRecords ? "PUT" : "PATCH"
        
        let batches: [URLRequest] = records
            .chunked(by: Self.batchLimit)
            .map { requestEncoder.encodeRecords($0, shouldAddID: true) }
            .compactMap { buildRequest(method: method, path: tableName, payload: $0) }
        
        var results = [Record]()

        for request in batches {
            let response = try await performRequest(request, decoder: self.responseDecoder.decodeRecords(data:))
            results.append(contentsOf: response)
        }
        
        return results
    }
    
    // MARK: - Detele records from a table
    
    /// Deletes a record from a table.
    ///
    /// - Parameters:
    ///   - tableName: Name of the table where the record is
    ///   - recordID: The id of the record to delete.
    /// - Returns: A publisher with either the record which was deleted or an error
    public func delete(tableName: String, recordID: String) async throws -> Record {
        let request = buildRequest(method: "DELETE", path: "\(tableName)/\(recordID)")
        return try await performRequest(request, decoder: responseDecoder.decodeDeleteResponse(data:))
    }
    
    /// Deletes multiple records by their ID.
    ///
    /// - Parameters:
    ///   - tableName: Name of the table where the records are.
    ///   - recordIDs: IDs of the records to be deleted.
    public func delete(tableName: String, recordIDs: [String]) async throws -> [Record] {
        let batches = recordIDs.map { URLQueryItem(name: "records[]", value: $0) }
            .chunked(by: Self.batchLimit)
            .map { buildRequest(method: "DELETE", path: tableName, queryItems: $0) }

        var results = [Record]()

        for request in batches {
            let response = try await performRequest(request, decoder: self.responseDecoder.decodeBatchDeleteResponse(data:))
            results.append(contentsOf: response)
        }
        
        return results
    }
    
}

// MARK: - Helpers

extension Airtable {

    func performRequest<T>(_ request: URLRequest?, decoder: @escaping (Data) throws -> T) async throws -> T {
        guard let urlRequest = request else {
            let error = AirtableError.invalidParameters(operation: #function, parameters: [request as Any])
            throw error
        }
        
        do {
            let response = try await URLSession.shared.data(for: urlRequest)
            let data = try errorHander.mapResponse(response)
            return try decoder(data)
        } catch {
            throw errorHander.mapError(error)
        }
    }
    
    func buildRequest(method: String, path: String, queryItems: [URLQueryItem]? = nil, payload: [String: Any]? = nil) -> URLRequest? {
        let url: URL?
        
        if let queryItems = queryItems {
            var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            components?.queryItems = queryItems
            url = components?.url
        } else {
            url = baseURL.appendingPathComponent(path)
        }
        
        guard let theURL = url else { return nil }
        
        var request = URLRequest(url: theURL)
        request.httpMethod = method
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        if let payload = payload {
            do {
                request.httpBody = try requestEncoder.asData(json: payload)
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                return nil
            }
        }
        
        return request
    }
}

