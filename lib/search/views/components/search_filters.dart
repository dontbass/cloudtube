import 'package:flutter/material.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/search/models/search_date.dart';
import 'package:clipious/search/models/search_duration.dart';
import 'package:clipious/search/models/search_sort_by.dart';
import 'package:clipious/utils.dart';

import '../../states/search.dart';

/// Кнопка фильтров: точка-индикатор, если фильтры не по умолчанию.
class SearchFiltersButton extends StatelessWidget {
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  const SearchFiltersButton({super.key, required this.filters, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Фильтры',
      onPressed: () async {
        final f = await showSafeModalBottomSheet<SearchFilters>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _FiltersSheet(initial: filters),
        );
        if (f != null) onChanged(f);
      },
      icon: Badge(isLabelVisible: !filters.isDefault, smallSize: 8, child: const Icon(Icons.tune_rounded)),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  final SearchFilters initial;

  const _FiltersSheet({required this.initial});

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late SearchFilters f = widget.initial;

  Widget _group<T>(String title, List<T> values, T selected, String Function(T) label, void Function(T) pick) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in values)
            ChoiceChip(
              showCheckmark: false,
              label: Text(label(v)),
              selected: v == selected,
              onSelected: (_) => setState(() => pick(v)),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locals = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Фильтры поиска', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          _group<SearchSortBy>(locals.searchSortBy, SearchSortBy.values, f.sortBy, (v) => v.getLabel(locals),
              (v) => f = f.copyWith(sortBy: v)),
          _group<SearchDate>(locals.searchUploadDate, SearchDate.values, f.date, (v) => v.getLabel(locals),
              (v) => f = f.copyWith(date: v)),
          _group<SearchDuration>(locals.searchDuration, SearchDuration.values, f.duration, (v) => v.getLabel(locals),
              (v) => f = f.copyWith(duration: v)),
          const SizedBox(height: 20),
          Row(children: [
            TextButton(
                onPressed: f.isDefault ? null : () => setState(() => f = const SearchFilters()), child: const Text('Сбросить')),
            const Spacer(),
            FilledButton(
                style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(140, 44)),
                onPressed: () => Navigator.of(context).pop(f),
                child: const Text('Применить')),
          ]),
        ]),
      ),
    );
  }
}
