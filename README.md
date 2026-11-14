# CloudTube для Android

Клиент [Invidious](https://invidious.io) для Android и Android TV в привычном виде мобильного YouTube:
лента во всю ширину, вкладки разделов, вертикальные Shorts со свайпом, комментарии в шторке,
страница видео с описанием и рекомендациями одной лентой.

Форк [Clipious](https://github.com/lamarios/clipious) (автор — lamarios). Лицензия AGPL-3.0, см. [LICENSE](LICENSE).
Проект не связан с YouTube и Google.

## Установка

APK — в [Releases](../../releases). Для большинства телефонов нужен файл `arm64-v8a`,
для старых — `armeabi-v7a`, для эмуляторов и некоторых приставок — `x86_64`.

При первом запуске укажите адрес своего сервера Invidious (например, `https://invidious.example.com`).
Если сервер закрыт паролем сайта (HTTP Basic Auth), добавьте его в настройках сервера:
«Вы» → «Сервер и пароль сайта».

Приложение само проверяет новые релизы на GitHub и предлагает обновиться
(«Вы» → «Проверить обновления»).

## Что умеет

- Главная, Подписки, Shorts, «Вы» — нижнее меню как в мобильном YouTube; Android TV — интерфейс Clipious
- Вкладки «Музыка», «Сейчас в эфире», «Новости», «Спорт», «Видеоигры», «Подкасты», «Фильмы»
- Shorts: вертикальная лента, предзагрузка следующих роликов, меню «Не интересует» / «Не рекомендовать канал»
- Комментарии с ответами, сортировка «популярные / новые»
- Вход в аккаунт Invidious: подписки, история, плейлисты
- SponsorBlock, проксирование видео через Invidious, загрузки, фоновое аудио, картинка-в-картинке (из Clipious)

## Серверные дополнения (необязательно)

С обычным Invidious приложение работает в совместимом режиме: «Главная» — популярное или тренды,
разделы — тренды и поиск, Shorts — поиск `#shorts`.

Папка [`server/`](server) — дополнения, которые ставятся рядом с Invidious и дают:

- персональную «Главную» (похожее на просмотренное + свежее из подписок + тренды);
- разделы «Навигатора» с подборками по популярности;
- Shorts из вкладок «Shorts» каналов — только вертикальные ролики, без трансляций, бесконечная лента;
- комментарии через yt-dlp, когда Invidious их не отдаёт;
- аватарки каналов в ленте.

Установка (Debian/Ubuntu, от root, Invidious уже работает):

```sh
git clone https://github.com/dontbass/cloudtube && cd cloudtube/server
INV_URL=http://127.0.0.1:3000 FEED_PORT=3200 REGION=RU HL=ru bash install.sh
```

Скрипт ставит yt-dlp и сервис `cloudtube-feed`, затем подсказывает строку `include`, которую нужно
добавить в `server { }` Invidious в nginx. Приложение находит дополнения само через `/ct-api/caps`.

## Сборка

Каждый push в `main` собирает APK в GitHub Actions (`.github/workflows/build.yml`) и публикует релиз.

Подпись берётся из секретов репозитория: `CT_KEYSTORE_B64` (base64 от `.jks`), `CT_STORE_PASSWORD`,
`CT_KEY_PASSWORD`, `CT_KEY_ALIAS`. Без них, например в форке, APK подписывается отладочным ключом.
Если делаете свой форк, поменяйте `kCtUpdateRepo` в `lib/cloudtube/updater.dart` и `applicationId`
в `android/app/build.gradle`.

Локально: Flutter 3.35.3,

```sh
flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter gen-l10n
flutter build apk --release --split-per-abi
```
