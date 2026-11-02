import 'package:cloud_firestore/cloud_firestore.dart';

class FirestorePageCursor {
  const FirestorePageCursor._(this.document);

  factory FirestorePageCursor.server(Map<String, dynamic> data) =
      ServerPageCursor;

  final QueryDocumentSnapshot<Map<String, dynamic>> document;
}

/// A trusted endpoint's ordering boundary, kept separate from document cursors.
class ServerPageCursor implements FirestorePageCursor {
  const ServerPageCursor(this.serverData);

  final Map<String, dynamic> serverData;

  @override
  QueryDocumentSnapshot<Map<String, dynamic>> get document =>
      throw StateError('A server cursor has no Firestore document');
}

class FirestorePage<T> {
  const FirestorePage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  final List<T> items;
  final FirestorePageCursor? cursor;
  final bool hasMore;
}

extension FirestoreQueryPager on Query<Map<String, dynamic>> {
  Future<FirestorePage<T>> getPage<T>({
    required T Function(QueryDocumentSnapshot<Map<String, dynamic>> document)
    decode,
    FirestorePageCursor? after,
    int pageSize = 50,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
    var query = this;
    if (after != null) {
      if (after is ServerPageCursor) {
        throw ArgumentError('Expected a Firestore cursor');
      }
      query = query.startAfterDocument(after.document);
    }
    final snapshot = await query.limit(pageSize + 1).get().timeout(timeout);
    final hasMore = snapshot.docs.length > pageSize;
    final documents = snapshot.docs.take(pageSize).toList(growable: false);
    return FirestorePage<T>(
      items: documents.map(decode).toList(growable: false),
      cursor: documents.isEmpty ? after : FirestorePageCursor._(documents.last),
      hasMore: hasMore,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAllPages({
    int pageSize = 200,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    assert(pageSize > 0);
    final documents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    Query<Map<String, dynamic>> next = this;
    while (true) {
      final snapshot = await next.limit(pageSize).get().timeout(timeout);
      documents.addAll(snapshot.docs);
      if (snapshot.docs.length < pageSize) return documents;
      next = startAfterDocument(snapshot.docs.last);
    }
  }
}
