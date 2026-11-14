<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/logo-dark.png">
  <img alt="CloudTube" src=".github/assets/logo-light.png" width="440">
</picture>

**Клиент [Invidious](https://invidious.io) для Android и Android TV в привычном виде мобильного YouTube**

[![Релиз](https://img.shields.io/github/v/release/dontbass/cloudtube?label=%D1%80%D0%B5%D0%BB%D0%B8%D0%B7&color=E85D4A)](https://github.com/dontbass/cloudtube/releases/latest)
[![Загрузки](https://img.shields.io/github/downloads/dontbass/cloudtube/total?label=%D0%B7%D0%B0%D0%B3%D1%80%D1%83%D0%B7%D0%BA%D0%B8&color=555)](https://github.com/dontbass/cloudtube/releases)
[![Сборка](https://img.shields.io/github/actions/workflow/status/dontbass/cloudtube/build.yml?label=%D1%81%D0%B1%D0%BE%D1%80%D0%BA%D0%B0)](https://github.com/dontbass/cloudtube/actions)
[![Лицензия](https://img.shields.io/github/license/dontbass/cloudtube?label=%D0%BB%D0%B8%D1%86%D0%B5%D0%BD%D0%B7%D0%B8%D1%8F&color=555)](LICENSE)
![Android 7+](https://img.shields.io/badge/Android-7%2B-3DDC84?logo=android&logoColor=white)

[**Скачать APK**](https://github.com/dontbass/cloudtube/releases/latest) · [Серверные дополнения](#серверные-дополнения) · [Сборка](#сборка)

</div>

---

CloudTube — форк [Clipious](https://github.com/lamarios/clipious), переработанный под интерфейс мобильного
YouTube. Видео идут через ваш сервер Invidious: без рекламы, без аккаунта Google и без трекинга.

## Возможности

|   |   |
|---|---|
| 🏠 **Привычная навигация** | Главная · Shorts · Подписки · «Вы» внизу, вкладки разделов сверху, лента во всю ширину |
| 📱 **Shorts** | Вертикальная лента со свайпом, предзагрузка следующих роликов, «Не интересует», «Не рекомендовать канал» |
| 🧭 **Разделы** | Музыка, Сейчас в эфире, Новости, Спорт, Видеоигры, Подкасты, Фильмы |
| 💬 **Комментарии** | Шторка как в YouTube, ответы, сортировка «популярные / новые» |
| ▶️ **Страница видео** | Описание, канал и подписка, лайки, рекомендации одной лентой |
| 👤 **Аккаунт Invidious** | Подписки, история, плейлисты |
| 🛡️ **Из Clipious** | SponsorBlock, проксирование видео, загрузки, фоновое аудио, картинка-в-картинке, Android TV |
| 🔄 **Обновления** | Приложение само находит новый релиз, скачивает и предлагает установить |

## Установка

1. Скачайте APK из [последнего релиза](https://github.com/dontbass/cloudtube/releases/latest):

   | Файл | Для чего |
   |---|---|
   | `…-arm64-v8a.apk` | почти все современные телефоны и приставки |
   | `…-armeabi-v7a.apk` | старые 32-битные устройства |
   | `…-x86_64.apk` | эмуляторы, некоторые ТВ-боксы |

2. При первом запуске укажите адрес своего сервера Invidious, например `https://invidious.example.com`.
   Если сайт закрыт паролем (HTTP Basic Auth), добавьте его в «Вы» → «Сервер и пароль сайта».
3. Новые версии приложение предложит само: «Вы» → «Проверить обновления».

> Нужен свой сервер Invidious или доступ к чужому. Публичные серверы перечислены на
> [docs.invidious.io/instances](https://docs.invidious.io/instances/).

## Серверные дополнения

Со стандартным Invidious всё работает в совместимом режиме: «Главная» — популярное или тренды, разделы — тренды
и поиск, Shorts — поиск `#shorts`.

Если сервер ваш, поставьте рядом с Invidious дополнения из папки [`server/`](server). Они дают:

- персональную «Главную»: похожее на просмотренное, свежее из подписок и тренды;
- разделы с подборками по популярности;
- Shorts из вкладок «Shorts» каналов: только вертикальные, без трансляций, бесконечная лента;
- комментарии через [yt-dlp](https://github.com/yt-dlp/yt-dlp), когда Invidious их не отдаёт;
- аватарки каналов в ленте.

```sh
git clone https://github.com/dontbass/cloudtube && cd cloudtube/server
sudo INV_URL=http://127.0.0.1:3000 FEED_PORT=3200 REGION=RU HL=ru bash install.sh
```

Скрипт ставит yt-dlp и сервис `cloudtube-feed` и подсказывает строку `include` для nginx.
Приложение находит дополнения само через `GET /ct-api/caps`.

## Сборка

Каждый push в `main` собирает APK в GitHub Actions и публикует релиз `v1.1.N`.

Подпись берётся из секретов репозитория: `CT_KEYSTORE_B64` (base64 от `.jks`), `CT_STORE_PASSWORD`,
`CT_KEY_PASSWORD`, `CT_KEY_ALIAS`. В форке без секретов APK подписывается отладочным ключом.
Для своего форка поменяйте `kCtUpdateRepo` в `lib/cloudtube/updater.dart` и `applicationId`
в `android/app/build.gradle`.

Локально, Flutter 3.35.3:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter build apk --release --split-per-abi
```

## Благодарности и лицензия

- [Clipious](https://github.com/lamarios/clipious) от lamarios — основа приложения
- [Invidious](https://github.com/iv-org/invidious), [yt-dlp](https://github.com/yt-dlp/yt-dlp),
  [SponsorBlock](https://sponsor.ajay.app), [river_player](https://github.com/lamarios/river_player)

Распространяется по [AGPL-3.0](LICENSE), как и Clipious.
CloudTube не связан с YouTube и Google. «YouTube» — товарный знак Google LLC.
