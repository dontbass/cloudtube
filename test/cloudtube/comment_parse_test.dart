import 'package:clipious/cloudtube/comments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('комментарий Invidious: аватар ближе к 48 px, ответы, отметки', () {
    final c = CtComment.fromJson({
      'author': 'Автор',
      'content': 'Текст',
      'publishedText': '2 дня назад',
      'likeCount': 15,
      'authorIsChannelOwner': true,
      'creatorHeart': {'creatorName': 'x'},
      'isEdited': true,
      'authorThumbnails': [
        {'url': 'big', 'width': 176},
        {'url': 'small', 'width': 32},
        {'url': 'mid', 'width': 48},
      ],
      'replies': {'replyCount': 3, 'continuation': 'C1'},
    })!;
    expect(c.author, 'Автор');
    expect(c.avatar, 'mid');
    expect(c.likes, 15);
    expect(c.replies, 3);
    expect(c.repliesContinuation, 'C1');
    expect(c.owner && c.heart && c.edited, isTrue);
  });

  test('новый формат: одна строка аватара, без лишних полей', () {
    final c = CtComment.fromJson({'author': 'A', 'contentHtml': 'B', 'authorThumbnail': 'u'})!;
    expect(c.avatar, 'u');
    expect(c.text, 'B');
    expect(c.likes, 0);
    expect(c.repliesContinuation, isNull);
  });

  test('действия от своего имени', () {
    final c = CtComment.fromJson({'author': 'A', 'content': 'B', 'ctReply': 'r', 'ctEditReply': 'e', 'ctDelete': 'd'})!;
    expect(c.replyParams, 'r');
    expect(c.editParams, 'e');
    expect(c.editIsReply, isTrue);
    expect(c.deleteAction, 'd');
  });

  test('мусор вместо комментария', () {
    expect(CtComment.fromJson(null), isNull);
    expect(CtComment.fromJson('строка'), isNull);
  });
}
