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

# Filtered key words to extract link
extract_filtered_links() {
    local dpi="$1" arch="$2" type="$3"
    awk -v dpi="$dpi" -v arch="$arch" -v type="$type" '
    BEGIN { block = ""; link = ""; found_dpi = found_arch = found_type = printed = 0 }
    /<a class="accent_color"/ {
        if (printed) next
        if (block != "" && link != "" && found_dpi && found_arch && found_type && !printed) { 
            print link; printed = 1 
        }
        block = $0; found_dpi = found_arch = found_type = 0
        if (match($0, /href="([^"]+)"/, arr)) link = arr[1]
    }
    { if (!printed) block = block "\n" $0 }
    /table-cell/ && $0 ~ dpi { found_dpi = 1 }
    /table-cell/ && $0 ~ arch { found_arch = 1 }
    /apkm-badge/ && $0 ~ (">" type "</span>") { found_type = 1 }
    END {
        if (block != "" && link != "" && found_dpi && found_arch && found_type && !printed)
            print link
    }
    '
}

# Get some versions of application on APKmirror pages 
get_apkmirror_version() {
    grep -oP 'class="fontBlack"[^>]*href="[^"]+"\s*>\K[^<]+' | sed 20q | awk '{print $NF}'
}

# Tải file APKM từ APKMirror theo cách của bạn
apkmirror() {
    local name="hay-day"
    local org="supercell"
    local dpi=""
    local arch="arm64-v8a"
    local type="BUNDLE"

    url="https://www.apkmirror.com/uploads/?appcategory=$name"
    version="${version:-$(req - "$url" | get_apkmirror_version | get_latest_version)}"
    url="https://www.apkmirror.com/apk/$org/$name/$name-${version//./-}-release"
    url="https://www.apkmirror.com$(req - "$url" | extract_filtered_links "$dpi" "$arch" "$type")"
    url="https://www.apkmirror.com$(req - "$url" | grep -oP 'class="[^"]*downloadButton[^"]*"[^>]*href="\K[^"]+')"
    url="https://www.apkmirror.com$(req - "$url" | grep -oP 'id="download-link"[^>]*href="\K[^"]+')"

    req "hay-day.apkm" "$url"
}

# Tải file APKM của Hay Day
echo "[*] Đang tải Hay Day từ APKMirror..."
apkmirror

# Kiểm tra nếu tải không thành công
APKM_FILE="hay-day.apkm"
if [ ! -f "$APKM_FILE" ]; then
    echo "[!] Lỗi: Không thể tải file APKM!"
    exit 1
fi
echo "[✔] Tải thành công: $APKM_FILE"

# Giải nén file APKM
EXTRACT_DIR="extracted_apkm"
echo "[*] Giải nén $APKM_FILE..."
unzip -o "$APKM_FILE" -d "$EXTRACT_DIR" || { echo "[!] Lỗi khi giải nén."; exit 1; }

# Kiểm tra cấu trúc thư mục sau khi giải nén
echo "[*] Kiểm tra cấu trúc thư mục sau khi giải nén..."
ls -R "$EXTRACT_DIR"

req APKEditor.jar https://github.com/REAndroid/APKEditor/releases/download/V1.4.2/APKEditor-1.4.2.jar
java -jar APKEditor.jar --verbose m -i "$EXTRACT_DIR" 

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
    --ks-pass pass:public --key-pass pass:public --out "$SIGNED_APK" "$FINAL_APK"

echo "[✔] APK đã được ký lại: $SIGNED_APK"
