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

    version=$(req "$url" - | grep -oP 'data-dt-version="\K[^"]*' | sed 10q | get_latest_version)
    [[ -z "$version" ]] && { echo "[!] Không tìm thấy phiên bản hợp lệ!"; exit 1; }

    url="https://apkpure.net/$name/$package/download/$version"
    download_link=$(req "$url" - | grep -oP '<a[^>]*id="download_link"[^>]*href="\K[^"]*' | head -n 1)

    if [[ -z "$download_link" ]]; then
        echo "[!] Không lấy được link tải xuống!"
        exit 1
    fi

    # Tạo thư mục tạm để tránh trùng tên file
    temp_dir=$(mktemp -d)
    
    # Tải file về thư mục tạm
    req "$download_link" -P "$temp_dir"

    # Lấy tên file thực tế vừa tải xuống
    filename=$(ls -t "$temp_dir" | head -n 1)

    # Di chuyển file về thư mục hiện tại
    mv "$temp_dir/$filename" .

    # Xóa thư mục tạm
    rmdir "$temp_dir"

    # Trả về tên file
    echo "$filename"
}

# Lấy APK từ apkpure
APKM_FILE=$(apkpure)
echo "File APK đã tải về: $APKM_FILE"

exit

# Kiểm tra nếu APK tải về không thành công
if [[ ! -f "$APKM_FILE" ]]; then
    echo "[!] Lỗi: Không tải được APK!"
    exit 1
fi

# Tải APKEditor
APK_EDITOR_URL="https://github.com/REAndroid/APKEditor/releases/download/V1.4.2/APKEditor-1.4.2.jar"
APK_EDITOR_JAR="APKEditor.jar"

req "$APK_EDITOR_URL" "$APK_EDITOR_JAR"

if [[ ! -f "$APK_EDITOR_JAR" ]]; then
    echo "[!] Lỗi: Không tải được APKEditor!"
    exit 1
fi

# Sử dụng APKEditor để chỉnh sửa APK
java -jar "$APK_EDITOR_JAR" m -i "$APKM_FILE"

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
MERGED_APK=$(ls *_merged.apk 2>/dev/null | head -n 1)

if [[ -z "$MERGED_APK" ]]; then
    echo "[!] Lỗi: Không tìm thấy file '_merged.apk' để ký!"
    exit 1
fi

"$APKSIGNER" sign --ks public.jks --ks-key-alias public \
    --ks-pass pass:public --key-pass pass:public --out "$SIGNED_APK" "$MERGED_APK"

echo "[✔] APK đã được ký lại: $SIGNED_APK"
