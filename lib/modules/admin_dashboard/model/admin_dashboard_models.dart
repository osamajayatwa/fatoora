import 'package:flutter/material.dart';

class DashboardStat {
  const DashboardStat({
    required this.titleKey,
    required this.value,
    required this.captionKey,
    required this.change,
    required this.icon,
    required this.color,
  });

  final String titleKey;
  final String value;
  final String captionKey;
  final String change;
  final IconData icon;
  final Color color;
}

class DashboardInvoice {
  const DashboardInvoice({
    required this.customer,
    required this.number,
    required this.amount,
    required this.statusKey,
    required this.statusColor,
  });

  final String customer;
  final String number;
  final String amount;
  final String statusKey;
  final Color statusColor;
}

class DashboardQuickAction {
  const DashboardQuickAction({
    required this.labelKey,
    required this.icon,
    required this.route,
  });

  final String labelKey;
  final IconData icon;
  final String route;
}

class DashboardSummaryItem {
  const DashboardSummaryItem({
    required this.labelKey,
    required this.amount,
    required this.percentage,
    required this.color,
  });

  final String labelKey;
  final String amount;
  final double percentage;
  final Color color;
}

class DashboardCustomer {
  const DashboardCustomer({required this.name, required this.amount});

  final String name;
  final String amount;
}

class DashboardAlert {
  const DashboardAlert({
    required this.messageKey,
    required this.date,
    required this.icon,
    required this.color,
  });

  final String messageKey;
  final String date;
  final IconData icon;
  final Color color;
}
