import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';

class CustomerReassignmentRequest {
  const CustomerReassignmentRequest(this.uid, this.reason);
  final String uid;
  final String reason;
}

class CustomerReassignmentDialog extends StatefulWidget {
  const CustomerReassignmentDialog({
    super.key,
    required this.customer,
    required this.candidates,
  });
  final CustomerModel customer;
  final List<AppUserModel> candidates;
  @override
  State<CustomerReassignmentDialog> createState() =>
      _CustomerReassignmentDialogState();
}

class _CustomerReassignmentDialogState
    extends State<CustomerReassignmentDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _selected;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('customers_reassign'.tr),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${'customers_current_assignee'.tr}: ${widget.customer.effectiveAssigneeName} (${widget.customer.effectiveAssigneeRole.tr})',
              ),
              const SizedBox(height: 12),
              Text('customers_reassign_warning'.tr),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('customer-new-assignee'),
                value: _selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'customers_new_assignee'.tr,
                ),
                items: widget.candidates
                    .where(
                      (candidate) =>
                          candidate.uid != widget.customer.effectiveAssigneeUid,
                    )
                    .map(
                      (candidate) => DropdownMenuItem(
                        value: candidate.uid,
                        child: Text(
                          '${candidate.name} (${candidate.role.tr})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selected = value),
                validator: (value) =>
                    value == null ? 'customers_assignee_required'.tr : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('customer-assignment-reason'),
                controller: _reason,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'customers_assignment_reason'.tr,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'customers_assignment_reason_required'.tr
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Get.back<CustomerReassignmentRequest>(),
        child: Text('cancel'.tr),
      ),
      FilledButton(
        key: const ValueKey('customer-assignment-confirm'),
        onPressed: () {
          if (_form.currentState!.validate()) {
            Get.back(
              result: CustomerReassignmentRequest(
                _selected!,
                _reason.text.trim(),
              ),
            );
          }
        },
        child: Text('customers_reassign_confirm'.tr),
      ),
    ],
  );
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }
}
