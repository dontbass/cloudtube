import 'package:bloc/bloc.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/search/models/db/search_history_item.dart';
import 'package:clipious/search/models/search_date.dart';
import 'package:clipious/search/models/search_duration.dart';
import 'package:clipious/search/models/search_sort_by.dart';

import '../../settings/states/settings.dart';

/// Фильтры поиска.
class SearchFilters {
  final SearchDate date;
  final SearchDuration duration;
  final SearchSortBy sortBy;

  const SearchFilters(
      {this.date = SearchDate.any, this.duration = SearchDuration.any, this.sortBy = SearchSortBy.relevance});

  bool get isDefault => date == SearchDate.any && duration == SearchDuration.any && sortBy == SearchSortBy.relevance;

  SearchFilters copyWith({SearchDate? date, SearchDuration? duration, SearchSortBy? sortBy}) => SearchFilters(
      date: date ?? this.date, duration: duration ?? this.duration, sortBy: sortBy ?? this.sortBy);

  /// Ключ для пересоздания списков результатов при смене фильтров.
  String get key => '${date.name}|${duration.name}|${sortBy.name}';
}

/// Состояние поиска. [text] — то, что сейчас в поле; [query] — то, что искали
/// (результаты не перезагружаются, пока человек печатает).
class SearchState {
  final String text;
  final String query;
  final bool showResults;
  final List<String> suggestions;
  final List<String> history;
  final SearchFilters filters;

  const SearchState(
      {this.text = '',
      this.query = '',
      this.showResults = false,
      this.suggestions = const [],
      this.history = const [],
      this.filters = const SearchFilters()});

  SearchState copyWith(
          {String? text,
          String? query,
          bool? showResults,
          List<String>? suggestions,
          List<String>? history,
          SearchFilters? filters}) =>
      SearchState(
          text: text ?? this.text,
          query: query ?? this.query,
          showResults: showResults ?? this.showResults,
          suggestions: suggestions ?? this.suggestions,
          history: history ?? this.history,
          filters: filters ?? this.filters);
}

class SearchCubit extends Cubit<SearchState> {
  final SettingsCubit settings;
  int _suggestSeq = 0;

  SearchCubit(this.settings, {String? query, bool searchNow = false})
      : super(SearchState(text: query ?? '')) {
    _loadHistory();
    if (searchNow && (query ?? '').trim().isNotEmpty) submit(query!);
  }

  @override
  Future<void> close() {
    EasyDebounce.cancel('search-suggestions');
    return super.close();
  }

  void _loadHistory() {
    emit(state.copyWith(history: settings.state.useSearchHistory ? db.getSearchHistory() : const []));
  }

  /// Человек печатает: прячем результаты и показываем подсказки.
  void onTextChanged(String t) {
    if (t == state.text && !state.showResults) return;
    emit(state.copyWith(text: t, showResults: false, suggestions: t.trim().isEmpty ? const [] : null));
    if (t.trim().isEmpty || settings.state.distractionFreeMode) return;
    final seq = ++_suggestSeq;
    EasyDebounce.debounce('search-suggestions', const Duration(milliseconds: 300), () async {
      try {
        final s = (await service.getSearchSuggestion(t)).suggestions;
        // ответ на старый текст не показываем
        if (!isClosed && seq == _suggestSeq) emit(state.copyWith(suggestions: s));
      } catch (_) {}
    });
  }

  Future<void> submit(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    _suggestSeq++;
    emit(state.copyWith(text: query, query: query, showResults: true));
    if (settings.state.useSearchHistory) {
      await db.addToSearchHistory(SearchHistoryItem(query, DateTime.now().millisecondsSinceEpoch ~/ 1000));
      if (!isClosed) _loadHistory();
    }
  }

  /// Вернуться к результатам (например, после того как стёрли и не стали искать).
  void showResults() {
    if (state.query.isNotEmpty) emit(state.copyWith(text: state.query, showResults: true));
  }

  void setFilters(SearchFilters f) => emit(state.copyWith(filters: f));

  Future<void> removeFromHistory(String e) async {
    await db.deleteFromSearchHistory(e);
    if (!isClosed) _loadHistory();
  }

  Future<void> clearHistory() async {
    for (final e in [...state.history]) {
      await db.deleteFromSearchHistory(e);
    }
    if (!isClosed) _loadHistory();
  }
}
