// Repository test doubles run without a Firebase app or network.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/firebase/trusted_callable_client.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'customer history query includes posted invoices while default list stays seller scoped',
    () async {
      final db = _Store();
      final repository = _repository(db);
      await repository.getInvoicesPage(
        companyId: 'company',
        customerId: 'customer',
        salesRepId: 'forged',
      );
      final filter = db.filter!;
      expect(
        _matches(filter, {
          'customerId': 'customer',
          'salesRepId': 'a',
          'invoiceStatus': 'confirmed',
          'financialPosted': true,
        }),
        isTrue,
      );
      expect(
        _matches(filter, {
          'customerId': 'customer',
          'salesRepId': 'a',
          'invoiceStatus': 'draft',
          'financialPosted': false,
        }),
        isFalse,
      );
      expect(
        _matches(filter, {
          'customerId': 'customer',
          'salesRepId': 'b',
          'invoiceStatus': 'draft',
          'financialPosted': false,
        }),
        isTrue,
      );
      expect(
        _matches(filter, {
          'customerId': 'unrelated',
          'salesRepId': 'a',
          'invoiceStatus': 'confirmed',
          'financialPosted': true,
        }),
        isFalse,
      );
      expect(db.sources, [Source.server]);
      for (final status in ['pendingSubmit', 'accepted', 'rejected']) {
        expect(
          _matches(filter, {
            'customerId': 'customer',
            'salesRepId': 'a',
            'invoiceStatus': status,
            'financialPosted': true,
          }),
          isTrue,
        );
      }
      await repository.getInvoicesPage(companyId: 'company');
      expect(_matches(db.filter!, {'salesRepId': 'a'}), isFalse);
      expect(_matches(db.filter!, {'salesRepId': 'b'}), isTrue);
    },
  );

  test(
    'invoice details recheck server assignment on every read and preserve seller',
    () async {
      final db = _Store();
      db.documents['companies/company/invoices/old'] = {
        'companyId': 'company',
        'customerId': 'customer',
        'salesRepId': 'a',
        'invoiceStatus': 'confirmed',
        'financialPosted': true,
      };
      db.documents['companies/company/customers/customer'] = {
        'companyId': 'company',
        'createdByUid': 'a',
        'assignmentVersion': 1,
        'assignedToUid': 'b',
      };
      final repository = _repository(db);
      expect(
        (await repository.getInvoiceById(
          companyId: 'company',
          invoiceId: 'old',
        ))!.salesRepId,
        'a',
      );
      for (final status in ['pendingSubmit', 'accepted', 'rejected']) {
        db.documents['companies/company/invoices/old']!['invoiceStatus'] =
            status;
        expect(
          (await repository.getInvoiceById(
            companyId: 'company',
            invoiceId: 'old',
          ))!.salesRepId,
          'a',
        );
      }
      db.documents['companies/company/customers/customer']!['assignedToUid'] =
          'c';
      await expectLater(
        repository.getInvoiceById(companyId: 'company', invoiceId: 'old'),
        throwsA(
          isA<InvoiceRepositoryException>().having(
            (e) => e.error,
            'error',
            InvoiceRepositoryError.permissionDenied,
          ),
        ),
      );
      expect(db.sources, everyElement(Source.server));
    },
  );

  test('historical read exception never admits another seller draft', () async {
    final db = _Store();
    db.documents['companies/company/invoices/old'] = {
      'companyId': 'company',
      'salesRepId': 'a',
      'invoiceStatus': 'draft',
    };
    await expectLater(
      _repository(db).getInvoiceById(companyId: 'company', invoiceId: 'old'),
      throwsA(isA<InvoiceRepositoryException>()),
    );
  });
}

InvoiceRepository _repository(_Store db) => InvoiceRepository(
  firestore: db,
  contextReader: _Context(),
  trustedCallableClient: _Callable(),
);

bool _matches(Map<String, Object?> filter, Map<String, Object?> row) {
  final op = filter['op'];
  if (op == 'AND' || op == 'OR') {
    final children = (filter['queries'] as List).cast<Map<String, Object?>>();
    return op == 'AND'
        ? children.every((f) => _matches(f, row))
        : children.any((f) => _matches(f, row));
  }
  return row[(filter['fieldPath'] as FieldPath).components.join('.')] ==
      filter['value'];
}

class _Context implements BusinessUserContextReader {
  @override
  Future<BusinessUserContext> requireApprovedUser() async =>
      const BusinessUserContext(
        uid: 'b',
        name: 'B',
        email: '',
        phone: '',
        role: 'sales_rep',
        companyId: 'company',
        active: true,
        approvalStatus: 'approved',
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Callable implements TrustedCallableClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final sources = <Source?>[];
  Map<String, Object?>? filter;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(store, '${this.path}/$path');
  @override
  Query<Map<String, dynamic>> where(
    Object fieldOrFilter, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    store.filter = (fieldOrFilter as Filter).toJson();
    return this;
  }

  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => this;
  @override
  Query<Map<String, dynamic>> limit(int limit) => this;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    store.sources.add(options?.source);
    return _Snapshot();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(store, '$path/$collectionPath');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    store.sources.add(options?.source);
    return _DocumentSnapshot(path.split('/').last, store.documents[path]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _DocumentSnapshot(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic>? value;
  @override
  Map<String, dynamic>? data() => value;
  @override
  bool get exists => value != null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
