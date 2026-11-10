import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/features/settings/data/models/accounting_configuration_model.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';
import 'package:fatoora/features/settings/controllers/settings_controller.dart';
import 'package:fatoora/features/settings/view/widgets/settings_section_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AccountingConfigurationScreen extends StatelessWidget {
  const AccountingConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) => SettingsSectionScaffold(
    titleKey: 'accounting_setup',
    subtitleKey: 'accounting_setup_subtitle',
    icon: Icons.account_tree_outlined,
    adminOnly: true,
    child: SettingsRepository.accountingConfigurationEnabled
        ? _editor()
        : Text('accounting_setup_unavailable'.tr),
  );

  Widget _editor() {
    // Pin the company of the opened settings page across asynchronous retries.
    final companyId = Get.find<SettingsController>().companyId;
    return AccountingConfigurationEditor(
      load: (id) => Get.find<SettingsRepository>().accountingConfiguration(
        id,
        companyId: companyId,
      ),
      save: (id, revision, configuration) =>
          Get.find<SettingsRepository>().accountingConfiguration(
            id,
            companyId: companyId,
            expectedRevision: revision,
            configuration: configuration,
          ),
    );
  }
}

typedef LoadAccountingConfiguration =
    Future<AccountingConfigurationSnapshot> Function(String bookId);
typedef SaveAccountingConfiguration =
    Future<AccountingConfigurationSnapshot> Function(
      String bookId,
      int revision,
      Map<String, dynamic> configuration,
    );

/// Forms share the existing settings route and trusted repository. No client writes.
class AccountingConfigurationEditor extends StatefulWidget {
  const AccountingConfigurationEditor({
    super.key,
    required this.load,
    required this.save,
  });
  final LoadAccountingConfiguration load;
  final SaveAccountingConfiguration save;
  @override
  State<AccountingConfigurationEditor> createState() =>
      _AccountingConfigurationEditorState();
}

class _AccountingConfigurationEditorState
    extends State<AccountingConfigurationEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  TextEditingController field(String key) =>
      _fields.putIfAbsent(key, TextEditingController.new);
  List<Map<String, dynamic>> _accounts = [], _periods = [], _taxCodes = [];
  Map<String, dynamic> _mappings = {};
  AccountingConfigurationSnapshot? _snapshot;
  Map<String, dynamic>? _pending;
  bool _busy = false, _loaded = false, _dirty = false;
  String? _error;
  String _taxStatus = 'unconfirmed',
      _priceBasis = '',
      _financialCoverage = 'unknown',
      _quantityCoverage = 'unknown';
  static const _roles = [
    'companyCash',
    'representativeCash',
    'receivables',
    'sales',
    'salesReturns',
    'operatingExpense',
    'representativePayable',
    'customerCredits',
    'outputTax',
    'bankClearing',
  ];
  static const _types = ['asset', 'liability', 'equity', 'income', 'expense'];
  static const _controls = [
    'none',
    'cash',
    'receivable',
    'payable',
    'customer_credit',
    'tax',
    'clearing',
  ];

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _id(String prefix) =>
      '${prefix}_${List.generate(12, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  void _changed() {
    if (mounted) setState(() => _dirty = true);
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'accounting_required'.tr : null;
  String? _integer(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null ? 'accounting_integer_required'.tr : null;
  }

  String _label(String key) => 'accounting_$key'.tr;

  Future<void> _load() async {
    if (_busy || _pending != null || _required(field('bookId').text) != null) {
      return;
    }
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_label('reload')),
          content: Text(_label('discard_changes')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_label('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_label('reload')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await widget.load(field('bookId').text.trim());
      if (!mounted) return;
      final c = snapshot.configuration;
      if (c != null) {
        for (final key in [
          'name',
          'currency',
          'moneyScale',
          'quantityScale',
          'priceScale',
          'fiscalYearStartMonth',
          'fiscalYearStartDay',
        ]) {
          field(key).text = c[key].toString();
        }
        final tax = c['taxPolicy'] as Map,
            opening = c['openingBoundary'] as Map;
        _taxStatus = tax['status'] as String;
        _priceBasis = tax['priceBasis'] as String? ?? '';
        field('taxEvidence').text = tax['evidenceRef'] as String? ?? '';
        field('cutoverDate').text = opening['cutoverDate'] as String? ?? '';
        field('openingEvidence').text = (opening['evidenceRefs'] as List).join(
          '\n',
        );
        field('retainedEarningsTreatment').text =
            opening['retainedEarningsTreatment'] as String? ?? '';
        _financialCoverage = opening['financialCoverage'] as String;
        _quantityCoverage = opening['quantityCoverage'] as String;
        _accounts = (c['accounts'] as List)
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        _periods = (c['periods'] as List)
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        _taxCodes = (c['taxCodes'] as List)
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        _mappings = Map<String, dynamic>.from(c['mappings'] as Map);
      } else {
        for (final e in _fields.entries) {
          if (e.key != 'bookId') e.value.clear();
        }
        _accounts = [];
        _periods = [];
        _taxCodes = [];
        _mappings = {};
        _taxStatus = 'unconfirmed';
        _priceBasis = '';
        _financialCoverage = 'unknown';
        _quantityCoverage = 'unknown';
      }
      setState(() {
        _snapshot = snapshot;
        _loaded = true;
        _dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _configuration() {
    String? nullable(String key) =>
        field(key).text.trim().isEmpty ? null : field(key).text.trim();
    return {
      'schemaVersion': 1,
      'name': field('name').text.trim(),
      'currency': field('currency').text.trim(),
      for (final key in [
        'moneyScale',
        'quantityScale',
        'priceScale',
        'fiscalYearStartMonth',
        'fiscalYearStartDay',
      ])
        key: int.parse(field(key).text),
      'timezone': 'Asia/Amman',
      'inventoryMode': 'quantity_only',
      'costCoverage': 'not_recorded',
      'accounts': _accounts,
      'periods': _periods,
      'mappings': _mappings,
      'taxCodes': _taxCodes,
      'taxPolicy': {
        'status': _taxStatus,
        'priceBasis': _priceBasis.isEmpty ? null : _priceBasis,
        'evidenceRef': nullable('taxEvidence'),
      },
      'openingBoundary': {
        'cutoverDate': nullable('cutoverDate'),
        'financialCoverage': _financialCoverage,
        'quantityCoverage': _quantityCoverage,
        'evidenceRefs': field('openingEvidence').text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'retainedEarningsTreatment': nullable('retainedEarningsTreatment'),
      },
    };
  }

  Future<void> _save() async {
    if (_busy || !_loaded) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _pending ??=
        jsonDecode(jsonEncode(_configuration())) as Map<String, dynamic>;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.save(
        _snapshot!.bookId,
        _snapshot!.revision,
        _pending!,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        final c = result.configuration!;
        _accounts = (c['accounts'] as List)
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        _periods = (c['periods'] as List)
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        _taxCodes = (c['taxCodes'] as List)
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        _mappings = Map<String, dynamic>.from(c['mappings'] as Map);
        _pending = null;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is FirebaseFunctionsException &&
          [
            'aborted',
            'already-exists',
            'invalid-argument',
            'permission-denied',
            'unauthenticated',
            'failed-precondition',
          ].contains(e.code)) {
        _pending = null;
      }
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) {
    if (e is FirebaseFunctionsException) {
      if (e.code == 'aborted' || e.code == 'already-exists') {
        return _label('conflict');
      }
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        return _label('access_denied');
      }
      if (e.code == 'invalid-argument') return _label('invalid_configuration');
      if (e.code == 'failed-precondition') return _label('setup_unavailable');
    }
    return _label('request_failed');
  }

  Widget _input(
    String key, {
    bool required = false,
    bool integer = false,
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey('accounting-$key'),
      controller: field(key),
      enabled: !_busy && _pending == null,
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: _label(key),
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      keyboardType: integer ? TextInputType.number : TextInputType.text,
      validator: integer
          ? _integer
          : required
          ? _required
          : null,
      onChanged: (_) => _changed(),
    ),
  );
  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_label(title), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
  Widget _select(
    String key,
    String value,
    List<String> options,
    ValueChanged<String> changed, {
    Map<String, String>? labels,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$key-$value-${options.join()}'),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _label(key),
        border: const OutlineInputBorder(),
      ),
      items: {...options, value}
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(
                labels?[v] ?? (v.isEmpty ? _label('not_selected') : _label(v)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _busy || _pending != null
          ? null
          : (v) {
              if (v != null) {
                changed(v);
                _changed();
              }
            },
    ),
  );

  Future<void> _edit(String kind, [int? index]) async {
    final rows = kind == 'account'
        ? _accounts
        : kind == 'period'
        ? _periods
        : _taxCodes;
    final existing = index == null ? null : rows[index];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ConfigurationRowDialog(
        kind: kind,
        existing: existing,
        accounts: _accounts,
        newId: existing?['id'] as String? ?? _id(kind),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        rows.add(result);
      } else {
        rows[index] = result;
      }
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_label('draft_notice')),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('accounting-bookId'),
          controller: field('bookId'),
          enabled: !_loaded && !_busy,
          decoration: InputDecoration(
            labelText: _label('bookId'),
            border: const OutlineInputBorder(),
          ),
          validator: _required,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('accounting-load'),
            onPressed: _busy || _pending != null ? null : _load,
            icon: const Icon(Icons.refresh),
            label: Text(_label(_loaded ? 'reload' : 'load')),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_loaded) ...[
          if (_snapshot!.revision > 0)
            Text('${_label('saved_revision')}: ${_snapshot!.revision}'),
          if (_pending != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_label('retry_pending')),
            ),
          AbsorbPointer(
            key: const ValueKey('accounting-editable-fields'),
            absorbing: _busy || _pending != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section('book', [
                  _input('name', required: true),
                  _input('currency', required: true),
                  _input('moneyScale', integer: true),
                  _input('quantityScale', integer: true),
                  _input('priceScale', integer: true),
                  _input('fiscalYearStartMonth', integer: true),
                  _input('fiscalYearStartDay', integer: true),
                  Text(_label('inventory_scope')),
                ]),
                _section('accounts', [
                  for (var i = 0; i < _accounts.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_accounts[i]['code']} · ${_accounts[i]['name']}',
                      ),
                      subtitle: Text(
                        '${_label(_accounts[i]['accountType'] as String)} · ${_label(_accounts[i]['control'] as String)}',
                      ),
                      trailing: IconButton(
                        tooltip: _label('edit'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit('account', i),
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _accounts.length >= 80
                          ? null
                          : () => _edit('account'),
                      icon: const Icon(Icons.add),
                      label: Text(_label('add_account')),
                    ),
                  ),
                ]),
                _section('mappings', [
                  for (final role in _roles)
                    _select(
                      role,
                      _mappings[role] as String? ?? '',
                      [
                        '',
                        ..._accounts
                            .where(
                              (a) =>
                                  a['active'] == true &&
                                  a['postingAllowed'] == true,
                            )
                            .map((a) => a['id'] as String),
                      ],
                      (v) {
                        if (v.isEmpty) {
                          _mappings.remove(role);
                        } else {
                          _mappings[role] = v;
                        }
                      },
                      labels: {
                        for (final a in _accounts)
                          a['id'] as String: '${a['code']} · ${a['name']}',
                      },
                    ),
                ]),
                _section('periods', [
                  for (var i = 0; i < _periods.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_periods[i]['name'] as String),
                      subtitle: Text(
                        '${_periods[i]['startsOn']} → ${_periods[i]['endsBefore']}',
                      ),
                      trailing: IconButton(
                        tooltip: _label('edit'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit('period', i),
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _periods.length >= 36
                          ? null
                          : () => _edit('period'),
                      icon: const Icon(Icons.add),
                      label: Text(_label('add_period')),
                    ),
                  ),
                ]),
                _section('tax_policy', [
                  _select('status', _taxStatus, [
                    'unconfirmed',
                    'documented',
                  ], (v) => _taxStatus = v),
                  _select('price_basis', _priceBasis, [
                    '',
                    'inclusive',
                    'exclusive',
                  ], (v) => _priceBasis = v),
                  _input('taxEvidence'),
                  for (var i = 0; i < _taxCodes.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_taxCodes[i]['code']} · ${_taxCodes[i]['ratePercent']}%',
                      ),
                      subtitle: Text(
                        '${_taxCodes[i]['startsOn']} → ${_taxCodes[i]['endsBefore']}',
                      ),
                      trailing: IconButton(
                        tooltip: _label('edit'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit('tax', i),
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _taxCodes.length >= 80
                          ? null
                          : () => _edit('tax'),
                      icon: const Icon(Icons.add),
                      label: Text(_label('add_tax')),
                    ),
                  ),
                ]),
                _section('opening', [
                  _input('cutoverDate', hint: 'YYYY-MM-DD'),
                  _select(
                    'financialCoverage',
                    _financialCoverage,
                    ['unknown', 'documented'],
                    (v) => _financialCoverage = v,
                  ),
                  _select(
                    'quantityCoverage',
                    _quantityCoverage,
                    ['unknown', 'documented'],
                    (v) => _quantityCoverage = v,
                  ),
                  _input('openingEvidence', lines: 3),
                  _input('retainedEarningsTreatment', lines: 3),
                  Text(_label('opening_notice')),
                ]),
              ],
            ),
          ),
          _section('readiness', [
            Text(
              _label(
                _dirty
                    ? 'save_to_validate'
                    : _snapshot!.configurationComplete
                    ? 'configuration_complete'
                    : 'configuration_incomplete',
              ),
            ),
            if (!_dirty)
              ..._snapshot!.missing.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• ${_label('missing_$m')}'),
                ),
              ),
            const SizedBox(height: 12),
            Text(_label('activation_pending')),
          ]),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('accounting-save'),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_label(_pending == null ? 'save_draft' : 'retry_save')),
          ),
        ],
      ],
    ),
  );
}

class _ConfigurationRowDialog extends StatefulWidget {
  const _ConfigurationRowDialog({
    required this.kind,
    required this.existing,
    required this.accounts,
    required this.newId,
  });
  final String kind, newId;
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> accounts;
  @override
  State<_ConfigurationRowDialog> createState() =>
      _ConfigurationRowDialogState();
}

class _ConfigurationRowDialogState extends State<_ConfigurationRowDialog> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late Map<String, dynamic> values;
  @override
  void initState() {
    super.initState();
    values = {...widget.existing ?? {}};
    for (final key in [
      'code',
      'name',
      'startsOn',
      'endsBefore',
      'ratePercent',
    ]) {
      fields[key] = TextEditingController(text: values[key]?.toString() ?? '');
    }
    values.putIfAbsent('accountType', () => 'asset');
    values.putIfAbsent('normalSide', () => 'debit');
    values.putIfAbsent('control', () => 'none');
    values.putIfAbsent('postingAllowed', () => true);
    values.putIfAbsent('active', () => true);
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String label(String k) => 'accounting_$k'.tr;
  Widget input(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: fields[key],
      decoration: InputDecoration(
        labelText: label(key),
        border: const OutlineInputBorder(),
      ),
      validator: (v) =>
          v == null || v.trim().isEmpty ? label('required') : null,
    ),
  );
  Widget select(
    String key,
    List<String> options, {
    Map<String, String>? labels,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      value: values[key] as String? ?? '',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label(key),
        border: const OutlineInputBorder(),
      ),
      items: options
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(
                labels?[v] ?? (v.isEmpty ? label('not_selected') : label(v)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => values[key] = v),
    ),
  );
  void submit() {
    if (!form.currentState!.validate()) return;
    final result = <String, dynamic>{};
    if (widget.kind == 'account') {
      result.addAll({
        'id': widget.newId,
        'code': fields['code']!.text.trim(),
        'name': fields['name']!.text.trim(),
        'parentId': values['parentId'] == null || values['parentId'] == ''
            ? null
            : values['parentId'],
        for (final key in [
          'accountType',
          'normalSide',
          'control',
          'postingAllowed',
          'active',
        ])
          key: values[key],
      });
    } else if (widget.kind == 'period') {
      result.addAll({
        'id': widget.newId,
        'name': fields['name']!.text.trim(),
        'startsOn': fields['startsOn']!.text.trim(),
        'endsBefore': fields['endsBefore']!.text.trim(),
      });
    } else {
      result.addAll({
        for (final key in ['code', 'ratePercent', 'startsOn', 'endsBefore'])
          key: fields[key]!.text.trim(),
        'outputAccountId': values['outputAccountId'] ?? '',
      });
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(label(widget.kind)),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.kind == 'account') ...[
                input('code'),
                input('name'),
                select(
                  'accountType',
                  _AccountingConfigurationEditorState._types,
                ),
                select('normalSide', ['debit', 'credit']),
                select(
                  'control',
                  _AccountingConfigurationEditorState._controls,
                ),
                select(
                  'parentId',
                  [
                    '',
                    ...widget.accounts
                        .where(
                          (a) =>
                              a['id'] != widget.newId &&
                              a['postingAllowed'] == false,
                        )
                        .map((a) => a['id'] as String),
                  ],
                  labels: {
                    for (final a in widget.accounts)
                      a['id'] as String: '${a['code']} · ${a['name']}',
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label('postingAllowed')),
                  value: values['postingAllowed'] == true,
                  onChanged: (v) =>
                      setState(() => values['postingAllowed'] = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label('active')),
                  value: values['active'] == true,
                  onChanged: (v) => setState(() => values['active'] = v),
                ),
              ] else ...[
                if (widget.kind == 'period')
                  input('name')
                else ...[
                  input('code'),
                  input('ratePercent'),
                  select(
                    'outputAccountId',
                    [
                      '',
                      ...widget.accounts
                          .where(
                            (a) =>
                                a['active'] == true &&
                                a['postingAllowed'] == true &&
                                a['control'] == 'tax' &&
                                a['accountType'] == 'liability',
                          )
                          .map((a) => a['id'] as String),
                    ],
                    labels: {
                      for (final a in widget.accounts)
                        a['id'] as String: '${a['code']} · ${a['name']}',
                    },
                  ),
                ],
                input('startsOn'),
                input('endsBefore'),
                Text(label('exclusive_end_notice')),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(label('cancel')),
      ),
      FilledButton(onPressed: submit, child: Text(label('apply'))),
    ],
  );
}
