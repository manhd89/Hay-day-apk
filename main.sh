#!/bin/bash

# Hàm gửi request giả lập như Firefox Android
req() {
    local output_file="$1"
    local url="$2"
    wget --header="User-Agent: Mozilla/5.0 (Android 13; Mobile; rv:125.0) Gecko/125.0 Firefox/125.0" \
         --header="Accept-Language: en-US,en;q=0.9" \
         --header="Connection: keep-alive" \
         --timeout=30 -nv -O "$output_file" "$url"
}

# Tìm phiên bản lớn nhất
max() {
    local max_version=""
    while read -r v; do
        [[ -z "$max_version" || ${v//[!0-9]/} -gt ${max_version//[!0-9]/} ]] && max_version="$v"
    done
    echo "$max_version"
}

# Lấy phiên bản mới nhất từ danh sách
get_latest_version() {
    grep -Evi 'alpha|beta' | grep -oP '\b\d+(\.\d+)+(?:\-\w+)?(?:\.\d+)?(?:\.\w+)?\b' | max
}

# Trích xuất link tải APK từ HTML
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

# Lấy danh sách phiên bản từ APKMirror
get_apkmirror_version() {
    grep -oP 'class="fontBlack"[^>]*href="[^"]+"\s*>\K[^<]+' | sed 20q | awk '{print $NF}'
}

# Tải file APKM từ APKMirror
apkmirror() {
    local name="hay-day"
    local org="supercell"
    local dpi=""
    local arch="arm64-v8a"
    local type="BUNDLE"

    local url="https://www.apkmirror.com/uploads/?appcategory=$name"
    local version
    version="$(req - - "$url" | get_apkmirror_version | get_latest_version)"
    if [[ -z "$version" ]]; then
        echo "[!] Không tìm thấy phiên bản hợp lệ!"
        exit 1
    fi

    url="https://www.apkmirror.com/apk/$org/$name/$name-${version//./-}-release"
    local download_page
    download_page="$(req - - "$url" | extract_filtered_links "$dpi" "$arch" "$type")"

    if [[ -z "$download_page" ]]; then
        echo "[!] Không tìm thấy link tải!"
        exit 1
    fi

    url="https://www.apkmirror.com$download_page"
    url="https://www.apkmirror.com$(req - - "$url" | grep -oP 'class="[^"]*downloadButton[^"]*"[^>]*href="\K[^"]+')"
    url="https://www.apkmirror.com$(req - - "$url" | grep -oP 'id="download-link"[^>]*href="\K[^"]+')"

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

# Kiểm tra xem có file base.apk không
if [ -f "$EXTRACT_DIR/base.apk" ]; then
    FINAL_APK="final.apk"
    SIGNED_APK="signed.apk"
    mv "$EXTRACT_DIR/base.apk" "$FINAL_APK"
    echo "[✔] Đã tìm thấy base.apk: $FINAL_APK"
else
    echo "[!] Lỗi: Không tìm thấy base.apk sau khi giải nén."
    exit 1
fi

# Xác định apksigner
APKSIGNER=$(command -v apksigner)
if [[ -z "$APKSIGNER" ]]; then
    APKSIGNER=$(find "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/build-tools" -name apksigner -type f | sort -r | head -n 1)
fi

# Kiểm tra chữ ký của APK
if [[ -n "$APKSIGNER" ]]; then
    echo "[*] Kiểm tra chữ ký APK..."
    if "$APKSIGNER" verify "$FINAL_APK"; then
        echo "[✔] APK đã có chữ ký hợp lệ."
    else
        echo "[!] APK chưa có chữ ký, tiến hành ký..."

        # Tạo khóa keystore nếu chưa có
        if [ ! -f "my-release-key.jks" ]; then
            echo "[*] Tạo khóa ký APK..."
            keytool -genkey -v -keystore my-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykeyalias -storepass password -key-pass password -dname "CN=Android, OU=Dev, O=Company, L=City, S=State, C=US"
        fi

        # Ký APK
        "$APKSIGNER" sign --ks my-release-key.jks --ks-key-alias mykeyalias --ks-pass pass:password --key-pass pass:password --out "$SIGNED_APK" "$FINAL_APK"
        echo "[✔] APK đã được ký lại: $SIGNED_APK"
    fi
else
    echo "[!] Không tìm thấy 'apksigner', bỏ qua bước kiểm tra chữ ký!"
fi

echo "[✔] Quá trình hoàn tất! File APK sẵn sàng để cài đặt."
