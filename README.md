# MyFin

Shaxsiy moliya boshqaruvi uchun iOS ilova (SwiftUI, iOS 26+, Liquid Glass).

## Imkoniyatlar

- Birinchi ishga tushirishda naqd pul, kartalar va qarzlarni kiritish
- Kartalar, naqd pul, jamg'arma va elektron hamyonlar (UZS, USD, EUR, RUB)
- Bank SMS (Uzcard/HUMO) va Apple Pay orqali avtomatik yozish (Shortcuts + App Intents)
- Qarzlar: men qarzdorman / menga qarzdor, qisman to'lovlar, muddat eslatmalari
- Byudjetlar (80%/100% ogohlantirish), maqsadlar, doimiy to'lovlar
- Tahlil: oylik kirim/chiqim, kategoriyalar, top joylar, tejash foizi
- MB (cbu.uz) valyuta kurslari va konvertor
- Face ID qulfi, summalarni yashirish, JSON zaxira va CSV eksport
- Siri / Shortcuts: balans, tezkor xarajat

## O'rnatish (SideStore)

SideStore → **Sources** → `+` →

```
https://github.com/BLCK7/MyFin/releases/latest/download/source.json
```

Har bir `main` push GitHub Actions'da imzosiz `.ipa` yig'adi va yangi reliz chiqaradi; SideStore yangilanishni o'zi ko'rsatadi.

## Build

```
brew install xcodegen
xcodegen generate
xcodebuild -scheme MyFin -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build
```
