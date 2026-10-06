import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sport/category_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';

/// Season: "26/27" … "30/31" (keeps an older/free value if one was saved).
class SeasonDropdown extends StatelessWidget {
  const SeasonDropdown(
      {super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = (value?.trim().isEmpty ?? true) ? null : value!.trim();
    return DropdownButtonFormField<String?>(
      key: ValueKey('season:$v'), // reflect values set from outside
      initialValue: v,
      isExpanded: true,
      decoration: InputDecoration(labelText: l.fieldSeason),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('—')),
        for (final s in seasonOptions)
          DropdownMenuItem<String?>(value: s, child: Text(s)),
        if (v != null && !seasonOptions.contains(v))
          DropdownMenuItem<String?>(value: v, child: Text(v)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Category by name, from the category list (built-in + edited + custom).
class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown(
      {super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final names = <String>[
      ...?ref
          .watch(categoryCatalogProvider)
          .valueOrNull
          ?.all
          .map((f) => f.name),
    ];
    final v = (value?.trim().isEmpty ?? true) ? null : value!.trim();
    return DropdownButtonFormField<String?>(
      // Rebuild when the list loads so the saved value shows up.
      key: ValueKey('${names.length}:$v'),
      initialValue: v,
      isExpanded: true,
      decoration: InputDecoration(labelText: l.fieldCategory),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('—')),
        for (final n in names)
          DropdownMenuItem<String?>(
              value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
        if (v != null && !names.contains(v))
          DropdownMenuItem<String?>(value: v, child: Text(v)),
      ],
      onChanged: onChanged,
    );
  }
}
