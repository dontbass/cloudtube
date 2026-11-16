<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/logo-dark.png">
  <img alt="CloudTube" src=".github/assets/logo-light.png" width="440">
</picture>

**YouTube без рекламы для Android, Android TV и Windows — напрямую или через свой сервер [Invidious](https://invidious.io)**

[![Релиз](https://img.shields.io/github/v/release/dontbass/cloudtube?label=%D1%80%D0%B5%D0%BB%D0%B8%D0%B7&color=E85D4A)](https://github.com/dontbass/cloudtube/releases/latest)
[![Загрузки](https://img.shields.io/github/downloads/dontbass/cloudtube/total?label=%D0%B7%D0%B0%D0%B3%D1%80%D1%83%D0%B7%D0%BA%D0%B8&color=555)](https://github.com/dontbass/cloudtube/releases)
[![Сборка](https://img.shields.io/github/actions/workflow/status/dontbass/cloudtube/build.yml?label=%D1%81%D0%B1%D0%BE%D1%80%D0%BA%D0%B0)](https://github.com/dontbass/cloudtube/actions)
[![Лицензия](https://img.shields.io/github/license/dontbass/cloudtube?label=%D0%BB%D0%B8%D1%86%D0%B5%D0%BD%D0%B7%D0%B8%D1%8F&color=555)](LICENSE)
![Android 7+](https://img.shields.io/badge/Android-7%2B-3DDC84?logo=android&logoColor=white)
![Windows 10+](https://img.shields.io/badge/Windows-10%2B-0078D4?logo=windows&logoColor=white)

[**Скачать APK**](https://github.com/dontbass/cloudtube/releases/latest) · [**Windows**](https://github.com/dontbass/cloudtube/releases/tag/windows-preview) · [Серверные дополнения](#серверные-дополнения) · [Сборка](#сборка)

</div>

---

CloudTube — форк [Clipious](https://github.com/lamarios/clipious), переработанный под интерфейс мобильного
YouTube. Работает **без сервера** (напрямую с YouTube) или **через ваш сервер Invidious**: без рекламы и без трекинга.

## Возможности

|   |   |
|---|---|
| ▶️ **Без сервера** | «Смотреть сразу»: видео, поиск, каналы, Shorts, комментарии прямо с YouTube — ничего настраивать не нужно |
| ⚡ **Быстрый старт** | Нажали на ролик — сразу плеер; данные одним запросом, как в NewPipe/SmartTube (≈0,5 с) |
| 🔑 **Аккаунт YouTube** | Вход кодом, как на телевизоре: ваши рекомендации, подписки, история. Пароль вводится только на сайте Google |
| 💬 **Комментарии** | Шторка как в YouTube, ответы, сортировка; писать, отвечать, изменять и удалять свои — от выбранного канала |
| 🏠 **Привычная навигация** | Главная · Shorts · Подписки · «Вы» внизу, разделы сверху: Музыка, Эфир, Новости, Спорт… |
| 📱 **Shorts** | Вертикальная лента со свайпом и предзагрузкой |
| 📺 **Android TV** | Управление пультом, масштаб интерфейса, автозапуск, вход в YouTube и на сервер с телефона по QR |
| 🖥️ **Windows** | Окно как сайт YouTube: плеер mpv, горячие клавиши, колонка рекомендаций |
| 🛠️ **Свой сервер** | Развёртывание Invidious на вашем VPS прямо из приложения, за 10–15 минут |
| 🛡️ **Из Clipious** | SponsorBlock, загрузки, фоновое аудио, картинка-в-картинке |
| 🔄 **Обновления** | Приложение само находит новый релиз и предлагает установить |
| 🩺 **Проверка скорости** | «Вы» → «Проверка скорости YouTube»: время каждого шага запуска видео на вашем устройстве |

## Установка

**Android и Android TV** — APK из [последнего релиза](https://github.com/dontbass/cloudtube/releases/latest):

| Файл | Для чего |
|---|---|
| `…-arm64-v8a.apk` | почти все современные телефоны и приставки |
| `…-armeabi-v7a.apk` | старые 32-битные устройства и ТВ-боксы |
| `…-x86_64.apk` | эмуляторы, некоторые ТВ-боксы |

**Windows 10/11** — `CloudTube-windows-x64.zip` из [windows-preview](https://github.com/dontbass/cloudtube/releases/tag/windows-preview):
распакуйте и запустите `cloudtube.exe` (установка не нужна).

При первом запуске выберите:

- **«Смотреть сразу»** — YouTube напрямую, без сервера;
- **«У меня есть сервер»** — адрес Invidious, например `https://invidious.example.com`; если сайт закрыт паролем
  (HTTP Basic Auth), логин и пароль вводятся там же;
- **«Развернуть свой сервер»** — см. ниже.

Режим можно сменить в любой момент: «Вы» → «Как смотреть».

## Аккаунт YouTube

- **Рекомендации, подписки, история** — «Вы» → «Войти в аккаунт YouTube» (на ТВ — «Вход в YouTube» в меню).
  Приложение показывает код и QR, код вводится на google.com/device с телефона или компьютера.
- **Комментарии от своего имени** — вход через сайт Google (откроется сам при первой отправке,
  или «Вы» → «Аккаунт для комментариев»). Там же — выбор канала, если их у почты несколько,
  второй аккаунт Google и выход. Так же устроены InnerTube/Metrolist: вход кодом YouTube для комментариев не принимает.

Вход хранится только на устройстве.

## Свой сервер за 10–15 минут

Свой сервер — это YouTube без рекламы для всей семьи и всех устройств, в том числе в браузере.
В приложении: **«Вы» → «Развернуть свой сервер»**. Нужны VPS (Debian 11+ / Ubuntu 20.04+,
от 1 ГБ памяти, root по паролю) и домен с A-записью на IP сервера. Приложение подключится по SSH и поставит
Invidious с companion, nginx, сертификат Let's Encrypt, пароль сайта, аккаунт и дополнения CloudTube.
Прогресс виден на экране, а в конце сервер сразу добавится в приложение.

То же без приложения, на сервере от root:

```sh
curl -fsSL https://raw.githubusercontent.com/dontbass/cloudtube/main/server/deploy.sh -o deploy.sh
CT_DOMAIN=video.example.com CT_USER=admin CT_PASS='пароль' bash deploy.sh
```

## Телевизор

- Пульт: стрелка влево у края — боковое меню, вправо — обратно к роликам; выбор ролика сразу запускает видео.
- «Настройки» → «Масштаб интерфейса», если всё слишком крупно.
- **Вход с телефона** (режим сервера): сканируете QR-код, вводите адрес сервера, пароль сайта и логин —
  телевизор подключается сам, данные идут по домашней сети напрямую на ТВ.
- **Вход в YouTube** (режим без сервера): код и QR на экране, подтверждение с телефона.

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

Каждый push в `main` собирает APK в GitHub Actions и публикует релиз `v1.1.N`; сборка Windows
публикуется в пререлиз `windows-preview`.

Подпись APK берётся из секретов репозитория: `CT_KEYSTORE_B64` (base64 от `.jks`), `CT_STORE_PASSWORD`,
`CT_KEY_PASSWORD`, `CT_KEY_ALIAS` — или один секрет `CLOUDTUBE` с тем же содержимым в виде строк
`ИМЯ = значение`. В форке без секретов APK подписывается отладочным ключом.
Для своего форка поменяйте `kCtUpdateRepo` в `lib/cloudtube/updater.dart` и `applicationId`
в `android/app/build.gradle`.

Локально, Flutter 3.35.3:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter build apk --release --split-per-abi   # Android
flutter build windows --release               # Windows
```

Режим без сервера использует [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart)
(исправленная копия — в `third_party/`) и собственные запросы InnerTube (`lib/cloudtube/yt_*.dart`).

## Благодарности и лицензия

- [Clipious](https://github.com/lamarios/clipious) от lamarios — основа приложения
- [Invidious](https://github.com/iv-org/invidious), [yt-dlp](https://github.com/yt-dlp/yt-dlp),
  [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart), [SmartTube](https://github.com/yuliskov/SmartTube) (вход кодом),
  [media_kit](https://github.com/media-kit/media-kit) (плеер Windows),
  [SponsorBlock](https://sponsor.ajay.app), [river_player](https://github.com/lamarios/river_player)

Распространяется по [AGPL-3.0](LICENSE), как и Clipious.
CloudTube не связан с YouTube и Google. «YouTube» — товарный знак Google LLC.
