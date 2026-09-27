//
//  TensorDecompression.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Compression
import Foundation
import CFpzip

/// Handles decompression of CCV tensors that may be compressed with zip (deflate) or fpzip codecs.
///
/// The CCV tensor binary format is:
/// - Bytes 0-3: UInt32 identifier (0 = uncompressed, 0x217 = deflate, 0xf7217 = fpzip)
/// - Bytes 4-67: ccv_nnc_tensor_param_t (type, format, datatype, reserved, dim[12])
/// - Bytes 68+: tensor data (raw or compressed)
struct TensorDecompression {

    enum DecompressionError: Error, CustomStringConvertible {
        case unsupportedCompression(UInt32)
        case deflateFailed
        case fpzipFailed
        case dataTooSmall

        var description: String {
            switch self {
            case .unsupportedCompression(let id):
                return "Unsupported tensor compression identifier: 0x\(String(id, radix: 16))"
            case .deflateFailed:
                return "Failed to decompress deflate-compressed tensor data"
            case .fpzipFailed:
                return "Failed to decompress fpzip-compressed tensor data"
            case .dataTooSmall:
                return "Tensor data is too small to contain a valid header"
            }
        }
    }

    // Compression identifiers from s4nnc Store.Codec
    private static let IDENTIFIER_UNCOMPRESSED: UInt32 = 0
    private static let IDENTIFIER_ZIP: UInt32 = 0x217
    private static let IDENTIFIER_FPZIP: UInt32 = 0xf7217

    // CCV data type constants
    private static let CCV_16F: UInt32 = 0x20000
    private static let CCV_32F: UInt32 = 0x04000
    private static let CCV_64F: UInt32 = 0x10000

    private static let HEADER_SIZE = 68

    /// Decompress tensor data if compressed, returning uncompressed tensor data.
    ///
    /// If the tensor is already uncompressed (identifier == 0), returns the data unchanged.
    /// Supports deflate (identifier 0x217) and fpzip (identifier 0xf7217) compression.
    ///
    /// - Parameter data: Raw tensor bytes (68-byte header + possibly compressed payload)
    /// - Returns: Tensor data with uncompressed payload
    static func decompressIfNeeded(_ data: Data) throws -> Data {
        guard data.count >= HEADER_SIZE else {
            throw DecompressionError.dataTooSmall
        }

        let identifier = data.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self)
        }

        if identifier == IDENTIFIER_UNCOMPRESSED {
            return data
        }

        // Read tensor params from header
        let datatype = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 12, as: UInt32.self) // offset 12 = datatype field
        }

        // Extract dimensions from header (dim[0..11] at offset 16)
        var dims = [Int32](repeating: 0, count: 12)
        data.withUnsafeBytes { ptr in
            for i in 0..<12 {
                dims[i] = ptr.load(fromByteOffset: 16 + i * 4, as: Int32.self)
            }
        }

        let compressedPayload = data.subdata(in: HEADER_SIZE..<data.count)

        let decompressedPayload: Data
        switch identifier {
        case IDENTIFIER_ZIP:
            decompressedPayload = try decompressDeflate(compressedPayload)
        case IDENTIFIER_FPZIP:
            decompressedPayload = try decompressFpzip(compressedPayload, datatype: datatype, dims: dims)
        default:
            throw DecompressionError.unsupportedCompression(identifier)
        }

        // Reconstruct uncompressed tensor: zero identifier + original params + decompressed data
        var result = Data(count: HEADER_SIZE)
        // Copy the original header (params at bytes 4-67)
        result.replaceSubrange(4..<HEADER_SIZE, with: data.subdata(in: 4..<HEADER_SIZE))
        // Set identifier to 0 (uncompressed)
        result.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(0), as: UInt32.self)
        }
        result.append(decompressedPayload)

        return result
    }

    // MARK: - Deflate Decompression

    /// Decompress raw DEFLATE data using Apple's Compression framework.
    private static func decompressDeflate(_ data: Data) throws -> Data {
        // Use a generous initial buffer; grow if needed
        var outputData = Data(count: data.count * 10)
        let decompressedSize = data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
            outputData.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) -> Int in
                let result = compression_decode_buffer(
                    dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    dstPtr.count,
                    srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    srcPtr.count,
                    nil,
                    COMPRESSION_ZLIB
                )
                return result
            }
        }

        if decompressedSize == 0 {
            throw DecompressionError.deflateFailed
        }

        // If the initial buffer was too small, retry with the exact size hint
        // compression_decode_buffer returns 0 on failure, or the output size
        // If it filled the buffer exactly, we might need more space
        if decompressedSize == outputData.count {
            // Retry with a larger buffer
            return try decompressDeflateStreaming(data)
        }

        outputData.count = decompressedSize
        return outputData
    }

    /// Streaming deflate decompression for large payloads.
    private static func decompressDeflateStreaming(_ data: Data) throws -> Data {
        var result = Data()
        let bufferSize = 65_536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }

        var status = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else {
            throw DecompressionError.deflateFailed
        }
        defer { compression_stream_destroy(stream) }

        data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) in
            stream.pointee.src_ptr = srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            stream.pointee.src_size = srcPtr.count

            repeat {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let have = bufferSize - stream.pointee.dst_size
                if have > 0 {
                    result.append(buffer, count: have)
                }
            } while status == COMPRESSION_STATUS_OK
        }

        guard status == COMPRESSION_STATUS_END else {
            throw DecompressionError.deflateFailed
        }

        return result
    }

    // MARK: - FPZIP Decompression

    /// Decompress fpzip-compressed tensor data.
    ///
    /// For Float16 tensors, fpzip stores Float32 data. After decompression,
    /// the Float32 values are converted back to Float16.
    private static func decompressFpzip(_ data: Data, datatype: UInt32, dims: [Int32]) throws -> Data {
        // Calculate total element count from dimensions
        var totalElements = 1
        for d in dims where d > 0 {
            totalElements *= Int(d)
        }

        guard totalElements > 0 else {
            throw DecompressionError.fpzipFailed
        }

        // Size of each element as stored by fpzip; Float16 tensors are stored as Float32
        // and narrowed after decoding.
        let fpzipElementSize: Int
        let isFP16: Bool

        switch datatype {
        case CCV_16F:
            fpzipElementSize = 4
            isFP16 = true
        case CCV_32F:
            fpzipElementSize = 4
            isFP16 = false
        case CCV_64F:
            fpzipElementSize = 8
            isFP16 = false
        default:
            throw DecompressionError.fpzipFailed
        }

        // Decompress using fpzip C library
        let decompressedFloat = try data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Data in
            guard let fpz = fpzip_read_from_buffer(UnsafeMutableRawPointer(mutating: srcPtr.baseAddress!)) else {
                throw DecompressionError.fpzipFailed
            }
            defer { fpzip_read_close(fpz) }

            guard fpzip_read_header(fpz) != 0 else {
                throw DecompressionError.fpzipFailed
            }

            let fpzipTotalElements = Int(fpz.pointee.nx) * Int(fpz.pointee.ny) * Int(fpz.pointee.nz) * Int(fpz.pointee.nf)

            let bufferSize = fpzipTotalElements * fpzipElementSize
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: fpzipElementSize)
            defer { buffer.deallocate() }

            guard fpzip_read(fpz, buffer) != 0 else {
                throw DecompressionError.fpzipFailed
            }

            if isFP16 {
                // Convert Float32 -> Float16 in place
                let floatPtr = buffer.assumingMemoryBound(to: Float.self)
                let outputSize = min(totalElements, fpzipTotalElements)
                var fp16Data = Data(count: outputSize * 2)
                fp16Data.withUnsafeMutableBytes { outPtr in
                    let uint16Ptr = outPtr.baseAddress!.assumingMemoryBound(to: UInt16.self)
                    for i in 0..<outputSize {
                        uint16Ptr[i] = floatToFloat16(floatPtr[i])
                    }
                }
                return fp16Data
            } else {
                let outputSize = min(totalElements, fpzipTotalElements) * fpzipElementSize
                return Data(bytes: buffer, count: outputSize)
            }
        }

        return decompressedFloat
    }

    /// Convert a Float32 value to Float16 (IEEE 754 half-precision) bit pattern.
    private static func floatToFloat16(_ value: Float) -> UInt16 {
        #if arch(arm64)
        return Float16(value).bitPattern
        #else
        let bits = value.bitPattern
        let sign = (bits >> 16) & 0x8000
        let exponent = Int((bits >> 23) & 0xFF) - 127 + 15
        let mantissa = bits & 0x7FFFFF

        if exponent <= 0 {
            if exponent < -10 {
                return UInt16(sign)
            }
            let m = (mantissa | 0x800000) >> (1 - exponent + 10)
            return UInt16(sign | (m >> 13))
        } else if exponent == 0xFF - 127 + 15 {
            if mantissa == 0 {
                return UInt16(sign | 0x7C00) // Infinity
            } else {
                return UInt16(sign | 0x7C00 | (mantissa >> 13)) // NaN
            }
        } else if exponent > 30 {
            return UInt16(sign | 0x7C00) // Overflow to infinity
        }

        return UInt16(sign | UInt32(exponent << 10) | (mantissa >> 13))
        #endif
    }
}
