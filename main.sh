#!/bin/bash

Hàm gửi request giả lập như Firefox Android

req() { wget --header="User-Agent: Mozilla/5.0 (Android 13; Mobile; rv:125.0) Gecko/125.0 Firefox/125.0" 
--header="Content-Type: application/octet-stream" 
--header="Accept-Language: en-US,en;q=0.9" 
--header="Connection: keep-alive" 
--header="Upgrade-Insecure-Requests: 1" 
--header="Cache-Control: max-age=0" 
--header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,/;q=0.8" 
--keep-session-cookies --timeout=30 -nv ${2:+-O "$2"} --content-disposition "$1" }

Tìm phiên bản lớn nhất

max() { local max=0 while read -r v || [ -n "$v" ]; do if [[ ${v//[!0-9]/} -gt ${max//[!0-9]/} ]]; then max=$v; fi done [[ $max = 0 ]] && echo "" || echo "$max" };

Lấy phiên bản mới nhất

get_latest_version() { grep -Evi 'alpha|beta' | grep -oPi '\b\d+(.\d+)+(?:-\w+)?(?:.\d+)?(?:.\w+)?\b' | max }

Lấy file tải xuống cuối cùng

get_latest_download() { find . -maxdepth 1 -type f -printf "%T@ %p\n" | sort -nr | awk 'NR==1{print $2}' }

apkpure() { name="spotify-music-and-podcasts-for-android" package="com.spotify.music" url="https://apkpure.net/$name/$package/versions"

version="${version:-$(req "$url" - | grep -oP 'data-dt-version="\K[^"]*' | sed 10q | get_latest_version)}"
url="https://apkpure.net/$name/$package/download/$version"

download_link=$(req "$url" - | grep -oP '<a[^>]*id="download_link"[^>]*href="\K[^"]*' | head -n 1)
filename=$(basename "$download_link" | sed 's/\?.*//')
req "$download_link" "$filename"

APKM_FILE=$(get_latest_download)
[[ -z "$APKM_FILE" ]] && { echo "[!] Lỗi: Không thể tải file APK!"; exit 1; }

# Sửa phần đổi tên file
local safe_name="Spotify"
local ext="${filename##*.}"
local new_name="${safe_name}_${version}_APKPure.${ext}"

# Xử lý đường dẫn tuyệt đối
new_name="${new_name//\//_}"
mv -f "$APKM_FILE" "./$new_name"
APKM_FILE="./$new_name"

echo "[✔] Tải thành công: $APKM_FILE"

}

apkpure

Tải APKEditor

req "https://github.com/REAndroid/APKEditor/releases/download/V1.4.2/APKEditor-1.4.2.jar" "APKEditor.jar" java -jar APKEditor.jar m -i "$APKM_FILE"

Xác định apksigner

if ! command -v apksigner &> /dev/null; then APKSIGNER=$(find "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/build-tools" -name apksigner -type f | sort -r | head -n 1) else APKSIGNER="apksigner" fi

[[ -z "$APKSIGNER" ]] && { echo "[!] Không tìm thấy 'apksigner'. Vui lòng cài đặt Android SDK Build-Tools!"; exit 1; }

Ký lại APK

echo "[*] Ký lại APK..." SIGNED_APK="signed.apk" "$APKSIGNER" sign --ks public.jks --ks-key-alias public 
--ks-pass pass:public --key-pass pass:public --out "$SIGNED_APK" *_merged.apk

echo "[✔] APK đã được ký lại: $SIGNED_APK"

