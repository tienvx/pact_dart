import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pact_dart/src/bindings/bindings.dart';
import 'package:pact_dart/gen/library.dart';
import 'package:pact_dart/src/errors.dart';
import 'package:pact_dart/src/utils/content_type.dart';
import 'package:pact_dart/src/interaction_handler.dart';

class Interaction extends InteractionHandler<Interaction> {
  Interaction(int pact, String description) : super(create(pact, description));

  static int create(int pact, String description) {
    final cDescription = description.toNativeUtf8().cast<Char>();

    try {
      return bindings.pactffi_new_interaction(pact, cDescription);
    } finally {
      calloc.free(cDescription);
    }
  }

  Interaction uponReceiving(String description) {
    if (description.isEmpty) {
      throw EmptyParameterError('description');
    }

    final cDescription = description.toNativeUtf8().cast<Char>();
    try {
      bindings.pactffi_upon_receiving(handle, cDescription);
    } finally {
      calloc.free(cDescription);
    }

    return this;
  }

  void _withHeaders(InteractionPart part, Map<String, dynamic> headers) {
    headers.forEach((key, value) {
      final cKey = key.toNativeUtf8().cast<Char>();
      Pointer<Char>? cValue;

      try {
        if (value is Map) {
          // Handle matcher map from PactMatchers
          cValue = jsonEncode(value).toNativeUtf8().cast<Char>();
          bindings.pactffi_with_header_v2(handle, part, cKey, 0, cValue);
        } else if (value is List) {
          // Handle multiple values as a list without matchers
          final json = {'value': value};
          cValue = jsonEncode(json).toNativeUtf8().cast<Char>();
          bindings.pactffi_with_header_v2(handle, part, cKey, 0, cValue);
        } else {
          // Simple string value
          cValue = value.toString().toNativeUtf8().cast<Char>();
          bindings.pactffi_with_header_v2(handle, part, cKey, 0, cValue);
        }
      } finally {
        calloc.free(cKey);
        if (cValue != null) {
          calloc.free(cValue);
        }
      }
    });
  }

  void _withBody<T>(InteractionPart part, T body, String? contentType) {
    Pointer<Char> cContentType;

    if (contentType != null) {
      cContentType = contentType.toNativeUtf8().cast<Char>();
    } else {
      cContentType = getContentType(body).toNativeUtf8().cast<Char>();
    }

    final cBody = jsonEncode(body).toNativeUtf8().cast<Char>();

    try {
      bindings.pactffi_with_body(handle, part, cContentType, cBody);
    } finally {
      calloc.free(cContentType);
      calloc.free(cBody);
    }
  }

  void _withBinaryBody<T>(InteractionPart part, T body, String? contentType) {
    Pointer<Char> cContentType = nullptr;

    if (contentType != null) {
      cContentType = contentType.toNativeUtf8().cast<Char>();
    }

    final binaryBody = _toUint8List(body);
    final cBody = _uint8ListToPointer(binaryBody);

    try {
      bindings.pactffi_with_binary_body(
          handle, part, cContentType, cBody, binaryBody.length);
    } finally {
      calloc.free(cContentType);
      calloc.free(cBody);
    }
  }

  void _withQuery(Map<String, dynamic> query) {
    query.forEach((key, value) {
      final cKey = key.toNativeUtf8().cast<Char>();
      Pointer<Char>? cValue;

      try {
        if (value is Map) {
          // Handle matcher map from PactMatchers
          cValue = jsonEncode(value).toNativeUtf8().cast<Char>();
          bindings.pactffi_with_query_parameter_v2(handle, cKey, 0, cValue);
        } else if (value is List) {
          // Handle multiple values as a list without matchers
          final json = {'value': value};
          cValue = jsonEncode(json).toNativeUtf8().cast<Char>();
          bindings.pactffi_with_query_parameter_v2(handle, cKey, 0, cValue);
        } else {
          // Simple string value
          cValue = value.toString().toNativeUtf8().cast<Char>();
          bindings.pactffi_with_query_parameter_v2(handle, cKey, 0, cValue);
        }
      } finally {
        calloc.free(cKey);
        if (cValue != null) {
          calloc.free(cValue);
        }
      }
    });
  }

  bool _isBinary(dynamic value) {
    return value is Uint8List ||
        value is ByteBuffer ||
        value is TypedData ||
        (value is List<int> && value.every((e) => e >= 0 && e <= 255));
  }

  Uint8List _toUint8List(dynamic value) {
    if (value == null) {
      throw ArgumentError('Value is null');
    }

    // Already Uint8List
    if (value is Uint8List) {
      return value;
    }

    // ByteBuffer
    if (value is ByteBuffer) {
      return value.asUint8List();
    }

    // Any TypedData (Int8List, Uint16List, etc.)
    if (value is TypedData) {
      return Uint8List.view(
        value.buffer,
        value.offsetInBytes,
        value.lengthInBytes,
      );
    }

    // List<int>
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }

    throw ArgumentError(
      'Unsupported binary type: ${value.runtimeType}',
    );
  }

  Pointer<Uint8> _uint8ListToPointer(Uint8List data) {
    final ptr = calloc<Uint8>(data.length);
    ptr.asTypedList(data.length).setAll(0, data);
    return ptr;
  }

  /// Configures the request for this interaction.
  ///
  /// The [method] and [path] are required.
  /// Query parameters can be specified using the [query] parameter, which accepts:
  /// - Simple string values
  /// - Lists for multiple values for the same parameter
  /// - PactMatchers matchers (recommended):
  ///   * PactMatchers.QueryRegex - Regex matching for values
  ///   * PactMatchers.QueryMultiValue - Multiple values for a parameter
  ///   * PactMatchers.QueryMultiRegex - Regex matching for multiple values
  ///   * PactMatchers.QueryLike - Type-based matching (infers the type)
  ///   * PactMatchers.QueryEachLike - Array of values of the same type
  Interaction withRequest<T>(String method, String path,
      {Map<String, dynamic>? headers,
      Map<String, dynamic>? query,
      T? body,
      String? contentType}) {
    if (method.isEmpty || path.isEmpty) {
      throw EmptyParametersError(['method', 'path']);
    }

    final cMethod = method.toNativeUtf8().cast<Char>();
    final cPath = path.toNativeUtf8().cast<Char>();

    try {
      bindings.pactffi_with_request(handle, cMethod, cPath);
    } finally {
      calloc.free(cMethod);
      calloc.free(cPath);
    }

    if (headers != null) {
      _withHeaders(InteractionPart.InteractionPart_Request, headers);
    }

    if (query != null) {
      _withQuery(query);
    }

    if (body != null) {
      if (_isBinary(body)) {
        _withBinaryBody(
            InteractionPart.InteractionPart_Request, body, contentType);
      } else {
        _withBody(InteractionPart.InteractionPart_Request, body, contentType);
      }
    }

    return this;
  }

  Interaction willRespondWith<T>(
    int status, {
    Map<String, dynamic>? headers,
    T? body,
    String? contentType,
  }) {
    bindings.pactffi_response_status(handle, status);

    if (headers != null) {
      _withHeaders(InteractionPart.InteractionPart_Response, headers);
    }

    if (body != null) {
      if (_isBinary(body)) {
        _withBinaryBody(
            InteractionPart.InteractionPart_Response, body, contentType);
      } else {
        _withBody(InteractionPart.InteractionPart_Response, body, contentType);
      }
    }

    return this;
  }
}
