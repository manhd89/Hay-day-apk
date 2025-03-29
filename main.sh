#!/bin/bash

# Hàm gửi request giả lập như Firefox Android
req() {
    wget --header="User-Agent: Mozilla/5.0 (Android 13; Mobile; rv:125.0) Gecko/125.0 Firefox/125.0" \
         --header="Accept-Language: en-US,en;q=0.9" \
         --header="Connection: keep-alive" \
         --timeout=30 -nv -O "$@"
}

# Find max version
max() {
    local max=0
    while read -r v || [ -n "$v" ]; do
        if [[ ${v//[!0-9]/} -gt ${max//[!0-9]/} ]]; then max=$v; fi
    done
    if [[ $max = 0 ]]; then echo ""; else echo "$max"; fi
}

# Get largest version (Just compatible with my way of getting versions code)
get_latest_version() {
    grep -Evi 'alpha|beta' | grep -oPi '\b\d+(\.\d+)+(?:\-\w+)?(?:\.\d+)?(?:\.\w+)?\b' | max
}

apkpure() {
    name="spotify-music-and-podcasts-for-android"
    package="com.spotify.music"
    url="https://apkpure.net/$name/$package/versions"
    version="${version:-$(req - $url | grep -oP 'data-dt-version="\K[^"]*' | sed 10q | get_latest_version)}"
    url="https://apkpure.net/$name/$package/download/$version"
    url=$(req - $url | grep -oP '<a[^>]*id="download_link"[^>]*href="\K[^"]*' | head -n 1)
    req $name-v$version.apk "$url"
}

# Tải file APKM của Hay Day
echo "[*] Đang tải Hay Day từ APKMirror..."
apkpure

# Kiểm tra nếu tải không thành công
APKM_FILE="$name-v$version.apk"
if [ ! -f "$APKM_FILE" ]; then
    echo "[!] Lỗi: Không thể tải file APKM!"
    exit 1
fi
echo "[✔] Tải thành công: $APKM_FILE"

req APKEditor.jar https://github.com/REAndroid/APKEditor/releases/download/V1.4.2/APKEditor-1.4.2.jar
java -jar APKEditor.jar m -i "$APKM_FILE"

# Xác định apksigner
if ! command -v apksigner &> /dev/null; then
    APKSIGNER=$(find "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/build-tools" -name apksigner -type f | sort -r | head -n 1)
else
    APKSIGNER="apksigner"
fi

if [[ -z "$APKSIGNER" ]]; then
    echo "[!] Không tìm thấy 'apksigner'. Vui lòng cài đặt Android SDK Build-Tools!"
    exit 1
fi

# Luôn ký lại APK
echo "[*] Ký lại APK..."

# Ký APK
"$APKSIGNER" sign --ks public.jks --ks-key-alias public \
    --ks-pass pass:public --key-pass pass:public --out signed.apk hay-day*.apk

echo "[✔] APK đã được ký lại: $SIGNED_APK"
