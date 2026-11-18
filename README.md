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

**CloudTube** — одно приложение, чтобы смотреть YouTube без рекламы на телефоне, телевизоре и компьютере.
Работает сразу, без настроек — напрямую с YouTube. А если хочется больше приватности и стабильности,
поднимите свой сервер Invidious — прямо из приложения, за 10–15 минут, — и переключайтесь между режимами одним тумблером.

## Зачем это и кому

- **Устали от рекламы, но не хотите платить за Premium** — CloudTube показывает видео без рекламы,
  а [SponsorBlock](https://sponsor.ajay.app) пропускает рекламные вставки внутри роликов.
- **Смотрите YouTube на телевизоре или приставке** — полноценная версия для пульта (и мыши), качество до 4K,
  вход в аккаунт по коду с телефона.
- **Хотите, чтобы Google знал о вас меньше** — смотрите без аккаунта или через свой сервер: тогда
  YouTube видит сервер, а не ваши устройства.
- **Хотите YouTube для всей семьи** — один свой сервер даёт YouTube без рекламы на всех телефонах, ТВ и в браузере;
  друзей можно пригласить ссылкой.
- **Пользуетесь несколькими устройствами** — одно приложение и один стиль на Android, Android TV и Windows.

## Чем отличается от других

Большинство альтернативных клиентов YouTube закрывают одну задачу: телефон **или** телевизор, работу напрямую
**или** через сервер. CloudTube собирает это вместе.

| | CloudTube | [NewPipe](https://newpipe.net) | [LibreTube](https://libretube.dev) | [SmartTube](https://github.com/yuliskov/SmartTube) | [Clipious](https://github.com/lamarios/clipious) |
|---|:-:|:-:|:-:|:-:|:-:|
| Телефон | ✅ | ✅ | ✅ | ограниченно | ✅ |
| Android TV (пульт) | ✅ | базово | базово | ✅ | ✅ |
| Windows | ✅ | — | — | — | — |
| Работает без сервера | ✅ | ✅ | ✅ | ✅ | — |
| Свой сервер (Invidious/Piped) | ✅ | — | ✅ Piped | — | ✅ |
| Переключение «напрямую ↔ сервер» в одно касание | ✅ | — | — | — | — |
| Развернуть свой сервер из приложения | ✅ | — | — | — | — |
| Вход в аккаунт YouTube: рекомендации, подписки | ✅ | — | — | ✅ | — |
| Писать комментарии от своего канала | ✅ | — | — | — | — |
| Вход на ТВ с телефона по QR | ✅ | — | — | — | — |

<sub>По открытым описаниям проектов на ноябрь 2026. Каждый из них хорош в своём — CloudTube многим им обязан (см. благодарности).</sub>

**Чего нет больше нигде:**

- 🛠️ **Свой сервер в два касания.** Приложение само подключается к вашему VPS по SSH и ставит Invidious, сайт
  в стиле YouTube, сертификат, пароль сайта и приглашения для друзей. Вам нужны только VPS и домен.
- 🔀 **Два режима в одном приложении.** Сервер упал или недоступен — тумблер «YouTube напрямую», и смотрите дальше;
  вход, подписки и история при этом не теряются.
- 📺 **Телевизор подключается с телефона.** Наводите камеру на QR на экране ТВ, вводите данные на телефоне —
  телевизор настраивается сам, без набора адресов и паролей пультом.

## Возможности

|   |   |
|---|---|
| ▶️ **Без сервера** | Видео, поиск, каналы, Shorts, комментарии прямо с YouTube — ничего настраивать не нужно |
| 🎞️ **Качество** | Свой DASH-проигрыватель: выбор качества до 4K, по умолчанию 1080p на телефоне и 4K на ТВ; быстрый старт и восстановление при обрывах |
| 🔑 **Аккаунт YouTube** | Вход кодом, как на телевизоре: ваши рекомендации, подписки, история. Пароль вводится только на сайте Google |
| 💬 **Комментарии** | Шторка как в YouTube, ответы, сортировка; писать, отвечать, изменять и удалять свои — от выбранного канала |
| 🏠 **Привычная навигация** | Главная · Shorts · Подписки · Профиль внизу, разделы сверху: Музыка, Эфир, Новости, Спорт… |
| 📱 **Shorts** | Вертикальная лента со свайпом и предзагрузкой |
| 📺 **Android TV** | Пульт и мышь, ряды как в SmartTube, предзагрузка, масштаб интерфейса, вход с телефона по QR |
| 🖥️ **Windows** | Один файл без установки, обновляется сам; окно как сайт YouTube, плеер mpv, горячие клавиши |
| 🔔 **Уведомления о новых видео** | По подпискам — в том числе без аккаунта и без сервера; колокольчик на канал и плейлист |
| ⬇️ **Загрузки** | Видео до 4K или только звук для просмотра без интернета |
| 🎨 **Темы** | Светлая, «Пергамент» (тёплая бумага, бережёт глаза), «Сумерки», тёмная |
| 🛡️ **Приватность** | Без рекламы и трекинга, SponsorBlock, DeArrow, картинка-в-картинке, фоновое аудио |
| 🔄 **Обновления** | Приложение само находит новый релиз и предлагает установить (Android и Windows) |

## Установка

**Android и Android TV** — APK из [последнего релиза](https://github.com/dontbass/cloudtube/releases/latest):

| Файл | Для чего |
|---|---|
| `…-arm64-v8a.apk` | почти все современные телефоны и приставки |
| `…-armeabi-v7a.apk` | старые 32-битные устройства и ТВ-боксы |
| `…-x86_64.apk` | эмуляторы, некоторые ТВ-боксы |

**Windows 10/11** — `CloudTube.exe` из [windows-preview](https://github.com/dontbass/cloudtube/releases/tag/windows-preview):
один файл, ничего не распаковывает и не устанавливает. Положите его в обычную папку («Документы», рабочий стол —
не в Program Files, чтобы он мог обновляться сам) и запустите. При первом запуске Windows может показать
«Система Windows защитила ваш компьютер» — «Подробнее» → «Выполнить в любом случае».
Если антивирус не доверяет упакованному файлу, есть запасной `CloudTube-windows-x64.zip`.

При первом запуске выберите:

- **«Смотреть сразу»** — YouTube напрямую, без сервера;
- **«У меня есть сервер»** — адрес Invidious, например `https://invidious.example.com`; если сайт закрыт паролем
  (HTTP Basic Auth), логин и пароль вводятся там же;
- **«Развернуть свой сервер»** — см. ниже.

Режим меняется в любой момент тумблером **«YouTube напрямую | Свой сервер»** в «Профиле» —
к своему серверу приложение вернётся с тем же адресом, входом и паролем сайта.

## Аккаунт YouTube

- **Рекомендации, подписки, история** — «Профиль» → «Войти в аккаунт YouTube» (на ТВ — «Вход в YouTube» в меню).
  Приложение показывает код и QR, код вводится на google.com/device с телефона или компьютера.
- **Комментарии от своего имени** — вход через сайт Google (откроется сам при первой отправке,
  или «Профиль» → «Аккаунт для комментариев»). Там же — выбор канала, если их у почты несколько,
  второй аккаунт Google и выход. Так же устроены InnerTube/Metrolist: вход кодом YouTube для комментариев не принимает.

Вход хранится только на устройстве.

## Свой сервер за 10–15 минут

Свой сервер — это YouTube без рекламы для всей семьи и всех устройств, в том числе в браузере.
В приложении: **«Профиль» → «Развернуть свой сервер»**. Нужны VPS (Debian 11+ / Ubuntu 20.04+,
от 1 ГБ памяти, root по паролю) и домен с A-записью на IP сервера. Приложение подключится по SSH и поставит
Invidious с companion, сайт CloudTube в виде YouTube (Materialious с логотипом и темой CloudTube, можно
установить как приложение — PWA), nginx, сертификат Let's Encrypt, пароль сайта, аккаунт, дополнения CloudTube
(лента, Shorts, эфиры, аватарки) и приглашения для друзей («Доступ» на сайте или `ctinvite new` в консоли).
Прогресс виден на экране, а в конце сервер сразу добавится в приложение.

То же без приложения, на сервере от root:

```sh
curl -fsSL https://raw.githubusercontent.com/dontbass/cloudtube/main/server/deploy.sh -o deploy.sh
CT_DOMAIN=video.example.com CT_USER=admin CT_PASS='пароль' bash deploy.sh
```

## Телевизор

- Пульт: стрелка влево у края — боковое меню, вправо — обратно к роликам; выбор ролика сразу запускает видео,
  долгое нажатие ОК — меню ролика (канал, подписка).
- Мышь (Bluetooth/USB): левая кнопка — выбор, долгое нажатие — меню ролика, правая — «Назад», колесо — прокрутка.
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
(однофайловый `CloudTube.exe` через Enigma Virtual Box и запасной zip) публикуется в пререлиз `windows-preview`.

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
