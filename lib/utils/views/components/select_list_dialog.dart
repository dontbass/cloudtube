import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';
import 'package:cloudtube/utils/states/select_list.dart';

class SelectList<T> extends StatelessWidget {
  final List<T>? values;
  final T? value;
  final String title;
  final Widget Function(T value, bool selected) itemBuilder;
  final Function(T value) onSelect;
  final Future<List<T>> Function(String filter)? asyncSearch;
  final bool Function(String filter, T value)? searchFilter;

  const SelectList(
      {super.key,
      required this.title,
      required this.values,
      this.value,
      required this.itemBuilder,
      required this.onSelect,
      this.searchFilter,
      this.asyncSearch})
      : assert(values == null || asyncSearch == null,
            'Cannot provide both async search and list of values');

  static show<T>(BuildContext context,
      {List<T>? values,
      T? value,
      Future<List<T>> Function(String filter)? asyncSearch,
      required Widget Function(T value, bool selected) itemBuilder,
      required Function(T value) onSelect,
      required String title,
      bool search = false,
      bool Function(String filter, T value)? searchFilter}) {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (ctx) => SelectList<T>(
        title: title,
        asyncSearch: asyncSearch,
        value: value,
        values: values,
        itemBuilder: itemBuilder,
        onSelect: onSelect,
        searchFilter: searchFilter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final locals = AppLocalizations.of(context)!;
    final searchable = searchFilter != null || asyncSearch != null;
    // высота по содержимому (раньше окно всегда было во весь экран, даже для 3 пунктов),
    // но не больше 70% экрана; со строкой поиска — постоянная, чтобы окно не прыгало
    final maxH = MediaQuery.sizeOf(context).height * 0.7;

    return AlertDialog(
      title: Text(title, style: textTheme.titleLarge),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      content: SizedBox(
        width: 340,
        height: searchable ? maxH : null,
        child: BlocProvider(
          create: (BuildContext context) =>
              SelectListCubit<T>(SelectListState<T>(filteredItems: values ?? [])),
          child: BlocBuilder<SelectListCubit<T>, SelectListState<T>>(builder: (context, state) {
            final cubit = context.read<SelectListCubit<T>>();
            final list = ListView.builder(
              shrinkWrap: !searchable,
              itemCount: state.filteredItems.length,
              itemBuilder: (context, index) {
                final item = state.filteredItems[index];
                final selected = item == value;
                // вся строка нажимается (раньше — только сам текст)
                return InkWell(
                  key: ValueKey(item),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    onSelect(item);
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Expanded(child: itemBuilder(item, selected)),
                      if (selected) Icon(Icons.check, color: colors.primary, size: 22),
                    ]),
                  ),
                );
              },
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (searchable)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(hintText: locals.search, prefixIcon: const Icon(Icons.search)),
                      onChanged: (q) => cubit.filterItems(asyncSearch, searchFilter, values, q),
                    ),
                  ),
                if (searchable)
                  Expanded(child: list)
                else
                  ConstrainedBox(constraints: BoxConstraints(maxHeight: maxH), child: list),
              ],
            );
          }),
        ),
      ),
    );
  }
}
