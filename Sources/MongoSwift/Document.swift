import Foundation
import libbson

public class Document: BsonValue, ExpressibleByDictionaryLiteral, CustomStringConvertible {
    internal var data: UnsafeMutablePointer<bson_t>!

    public var bsonType: BsonType { return .document }

    public init() {
        data = bson_new()
    }

    public init(fromData bsonData: UnsafeMutablePointer<bson_t>) {
        data = bsonData
    }

    public init(_ doc: [String: BsonValue?]) {
        data = bson_new()
        for (k, v) in doc {
            self[k] = v
        }
    }

   public required init(dictionaryLiteral doc: (String, Any?)...) {
        data = bson_new()
        for (k, v) in doc {
            self[k] = v as? BsonValue
        }
    }

    public func bsonAppend(data: UnsafeMutablePointer<bson_t>, key: String) -> Bool {
        return bson_append_document(data, key, Int32(key.count), self.data)
    }

    public func getData() -> UnsafeMutablePointer<bson_t> {
        return data
    }

    deinit {
        bson_destroy(data)
    }

    public var description: String {
        let json = bson_as_relaxed_extended_json(self.data, nil)
        guard let jsonData = json else {
            return String()
        }

        return String(cString: jsonData)
    }

    subscript(key: String) -> BsonValue? {
        get {
            var iter: bson_iter_t = bson_iter_t()
            if !bson_iter_init(&iter, data) {
                return nil
            }

            func retrieveErrorMsg(_ type: String) -> String {
                return "Failed to retrieve the \(type) value for key '\(key)'"
            }

            while bson_iter_next(&iter) {
                let ikey = String(cString: bson_iter_key(&iter))
                if ikey == key {
                    let itype = bson_iter_type(&iter)
                    switch itype {
                    case BSON_TYPE_ARRAY:
                        return [BsonValue].from(bson: &iter)

                    case BSON_TYPE_BINARY:
                        return Binary.from(bson: &iter)

                    case BSON_TYPE_BOOL:
                        return bson_iter_bool(&iter)

                    case BSON_TYPE_CODE, BSON_TYPE_CODEWSCOPE:
                        return CodeWithScope.from(bson: &iter)

                    case BSON_TYPE_DATE_TIME:
                        return Date(msSinceEpoch: bson_iter_date_time(&iter))

                    // DBPointer is deprecated, so convert to a DBRef doc.
                    case BSON_TYPE_DBPOINTER:
                        var length: UInt32 = 0
                        let collectionPP = UnsafeMutablePointer<UnsafePointer<Int8>?>.allocate(capacity: 1)
                        let oidPP = UnsafeMutablePointer<UnsafePointer<bson_oid_t>?>.allocate(capacity: 1)
                        bson_iter_dbpointer(&iter, &length, collectionPP, oidPP)

                        guard let oidP = oidPP.pointee else {
                            preconditionFailure(retrieveErrorMsg("DBPointer ObjectId"))
                        }
                        guard let collectionP = collectionPP.pointee else {
                            preconditionFailure(retrieveErrorMsg("DBPointer collection name"))
                        }

                        let dbRef: Document = [
                            "$ref": String(cString: collectionP),
                            "$id": ObjectId(from: oidP.pointee)
                        ]

                        return dbRef

                    case BSON_TYPE_DECIMAL128:
                        return Decimal128.from(bson: &iter)

                    case BSON_TYPE_DOCUMENT:
                        var length: UInt32 = 0
                        let document = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: 1)

                        bson_iter_document(&iter, &length, document)

                        guard let docData = bson_new_from_data(document.pointee, Int(length)) else {
                            preconditionFailure("Failed to create a bson_t from document data")
                        }

                        return Document(fromData: docData)

                    case BSON_TYPE_DOUBLE:
                        return bson_iter_double(&iter)

                    case BSON_TYPE_INT32:
                        return Int(bson_iter_int32(&iter))

                    case BSON_TYPE_INT64:
                        return bson_iter_int64(&iter)

                    case BSON_TYPE_MINKEY:
                        return MinKey()

                    case BSON_TYPE_MAXKEY:
                        return MaxKey()

                    // Since Undefined is deprecated, convert to null if we encounter it.
                    case BSON_TYPE_NULL, BSON_TYPE_UNDEFINED:
                        return nil

                    case BSON_TYPE_OID:
                        return ObjectId.from(bson: &iter)

                    case BSON_TYPE_REGEX:
                        do { return try NSRegularExpression.from(bson: &iter)
                        } catch {
                            preconditionFailure("Failed to create an NSRegularExpression object " +
                                "from regex data stored for key \(key)")
                        }

                    // Since Symbol is deprecated, return as a string instead.
                    case BSON_TYPE_SYMBOL:
                        var length: UInt32 = 0
                        let value = bson_iter_symbol(&iter, &length)
                        guard let strValue = value else {
                            preconditionFailure(retrieveErrorMsg("Symbol"))
                        }
                        return String(cString: strValue)

                    case BSON_TYPE_TIMESTAMP:
                        return Timestamp.from(bson: &iter)

                    case BSON_TYPE_UTF8:
                        var length: UInt32 = 0
                        let value = bson_iter_utf8(&iter, &length)
                        guard let strValue = value else {
                            preconditionFailure(retrieveErrorMsg("UTF-8"))
                        }

                        return String(cString: strValue)

                    default:
                        return nil
                    }
                }
            }

            return nil
        }

        set(newValue) {

            guard let value = newValue else {
                let res = bson_append_null(data, key, Int32(key.count))
                precondition(res, "Failed to set the value for key \(key) to null")
                return
            }

            let res = value.bsonAppend(data: data, key: key)
            precondition(res, "Failed to set the value for key '\(key)' to" +
                " \(String(describing: newValue)) with BSON type \(value.bsonType)")

        }
    }
}