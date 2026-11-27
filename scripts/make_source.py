import json
import sys
from datetime import date

version, build, size, repo = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
base = f"https://github.com/{repo}"
ipa = f"{base}/releases/download/v{version}/MyFin.ipa"
icon = f"https://raw.githubusercontent.com/{repo}/main/icon.png"
today = date.today().isoformat()
desc = ("Shaxsiy moliya boshqaruvi: kartalar, naqd pul, qarzlar, byudjet, maqsadlar va tahlil. "
        "Bank SMS va Apple Pay orqali avtomatik kuzatish. Liquid Glass dizayn.")
privacy = {
    "NSFaceIDUsageDescription": "MyFin moliyaviy ma'lumotlaringizni himoyalash uchun Face ID'dan foydalanadi.",
    "NSPhotoLibraryUsageDescription": "Hujjat rasmlarini shifrlangan seyfga qo'shish uchun.",
    "NSCameraUsageDescription": "Hujjat yoki chekni suratga olish uchun.",
}

source = {
    "name": "MyFin",
    "identifier": "uz.saminov.myfin.source",
    "subtitle": "Shaxsiy moliya",
    "description": desc,
    "iconURL": icon,
    "website": base,
    "tintColor": "#7C8CFF",
    "apps": [{
        "name": "MyFin",
        "bundleIdentifier": "uz.saminov.myfin",
        "developerName": "Saminov",
        "subtitle": "Shaxsiy moliya boshqaruvi",
        "localizedDescription": desc,
        "iconURL": icon,
        "tintColor": "#7C8CFF",
        "category": "utilities",
        "screenshotURLs": [],
        "versions": [{
            "version": version,
            "buildVersion": build,
            "date": today,
            "localizedDescription": f"Build #{build}",
            "downloadURL": ipa,
            "size": size,
            "minOSVersion": "26.0",
        }],
        "version": version,
        "versionDate": today,
        "versionDescription": f"Build #{build}",
        "downloadURL": ipa,
        "size": size,
        "appPermissions": {"entitlements": ["com.apple.security.application-groups"], "privacy": privacy},
    }],
    "news": [],
}
print(json.dumps(source, ensure_ascii=False, indent=2))
