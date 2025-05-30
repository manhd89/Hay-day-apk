#!/bin/bash

# Hàm gửi request giả lập như Firefox Android
req() {
    wget --header="User-Agent: Mozilla/5.0 (Android 13; Mobile; rv:125.0) Gecko/125.0 Firefox/125.0" \
         --header="Content-Type: application/octet-stream" \
         --header="Accept-Language: en-US,en;q=0.9" \
         --header="Connection: keep-alive" \
         --header="Upgrade-Insecure-Requests: 1" \
         --header="Cache-Control: max-age=0" \
         --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" \
         --keep-session-cookies --timeout=30 -nv ${2:+-O "$2"} --content-disposition "$1"
}

# Function to download necessary resources from GitHub
download_github() {
    name=$1
    repo=$2
    local github_api_url="https://api.github.com/repos/$name/$repo/releases/latest"
    local page=$(req "$github_api_url" - 2>/dev/null)
    local asset_urls=$(echo "$page" | jq -r '.assets[] | select(.name | endswith(".asc") | not) | "\(.browser_download_url) \(.name)"')
    while read -r download_url asset_name; do
        req "$download_url" "$asset_name"
    done <<< "$asset_urls"
}

# Tìm phiên bản lớn nhất
max() {
    local max=0
    while read -r v || [ -n "$v" ]; do
        num_ver=$(echo "$v" | grep -o '[0-9]\+' | paste -sd '')
        num_max=$(echo "$max" | grep -o '[0-9]\+' | paste -sd '')
        if [[ "$num_ver" -gt "$num_max" ]]; then max="$v"; fi
    done
    [[ $max = 0 ]] && echo "" || echo "$max"
}

# Lấy phiên bản mới nhất
get_latest_version() {
    grep -Evi 'alpha|beta' | grep -oPi '\b\d+(\.\d+)+(?:-\w+)?(?:\.\d+)?(?:\.\w+)?\b' | max
}

apkpure() {
    name="spotify-music-and-podcasts-for-android"
    package="com.spotify.music"
    url="https://apkpure.net/$name/$package/versions"

    #version=$(req "$url" - | grep -oP 'data-dt-version="\K[^"]*' | sed 10q | get_latest_version)
    #[[ -z "$version" ]] && { echo "[!] Không tìm thấy phiên bản hợp lệ!"; exit 1; }

    version="9.0.40.68"
    
    url="https://apkpure.net/$name/$package/download/$version"
    download_link=$(req "$url" - | grep -oP '<a[^>]*id="download_link"[^>]*href="\K[^"]*' | head -n 1)

    if [[ -z "$download_link" ]]; then
        echo "[!] Không lấy được link tải xuống!"
        exit 1
    fi

    # Lấy danh sách file trước khi tải
    before_download=(*)

    # Tải file về thư mục hiện tại, không đặt tên tùy chỉnh
    req "$download_link"

    # Lấy danh sách file sau khi tải
    after_download=(*)

    # Tìm file mới xuất hiện bằng cách so sánh danh sách trước & sau
    for file in "${after_download[@]}"; do
        if [[ ! " ${before_download[@]} " =~ " $file " ]]; then
            echo "$file"
            return
        fi
    done

    echo "[!] Lỗi: Không xác định được tên file!"
    exit 1
}

download_github "revanced" "revanced-patches"
download_github "revanced" "revanced-cli"

# Lấy APK từ apkpure
APKM_FILE=$(apkpure)
echo "File APK đã tải về: $APKM_FILE"

# Kiểm tra nếu APK tải về không thành công
if [[ ! -f "$APKM_FILE" ]]; then
    echo "[!] Lỗi: Không tải được APK!"
    exit 1
fi

# Kiểm tra nếu tệp tải về là file .xapk mới chạy merge
if [[ "$APKM_FILE" == *.xapk ]]; then
    echo "[*] File tải về là .xapk, tiến hành merge file..."
    
    # Tải APKEditor
    APK_EDITOR_URL="https://github.com/REAndroid/APKEditor/releases/download/V1.4.2/APKEditor-1.4.2.jar"
    APK_EDITOR_JAR="APKEditor.jar"

    req "$APK_EDITOR_URL" "$APK_EDITOR_JAR"

    if [[ ! -f "$APK_EDITOR_JAR" ]]; then
        echo "[!] Lỗi: Không tải được APKEditor!"
        exit 1
    fi

    # Sử dụng APKEditor để merge file
    java -jar "$APK_EDITOR_JAR" m -i "$APKM_FILE"

    java -jar revanced-cli*.jar patch --patches patches*.rvp --out "patched-spotify-v$version.apk" *_merged.apk

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

    # Ký lại APK
    echo "[*] Ký lại APK..."
    SIGNED_APK="signed.apk"

    "$APKSIGNER" sign --ks public.jks --ks-key-alias public \
        --ks-pass pass:public --key-pass pass:public --out "$SIGNED_APK" patched-spotify-v$version.apk

    echo "[✔] APK đã được ký lại: $SIGNED_APK"
else
    echo "[*] File tải về không phải .xapk, không cần merge."
fi
