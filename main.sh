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

# Tải bundletool.jar từ link khả dụng
BUNDLETOOL_JAR="bundletool.jar"
if [ ! -f "$BUNDLETOOL_JAR" ]; then
    echo "[*] Đang tải bundletool..."
    req "$BUNDLETOOL_JAR" "https://github.com/google/bundletool/releases/download/1.15.6/bundletool-all-1.15.6.jar"
fi

# Giải nén file APKM
EXTRACT_DIR="extracted_apkm"
echo "[*] Giải nén $APKM_FILE..."
unzip -o "$APKM_FILE" -d "$EXTRACT_DIR" || { echo "[!] Lỗi khi giải nén."; exit 1; }

# Hợp nhất Split APKs thành một APK duy nhất bằng extract-apks
FINAL_APK="final.apk"
SIGNED_APK="signed.apk"
echo "[*] Hợp nhất Split APKs..."
java -jar "$BUNDLETOOL_JAR" extract-apks --apks="$EXTRACT_DIR/base.apks" --output-dir="final_apk"
mv final_apk/*.apk "$FINAL_APK"

# Kiểm tra chữ ký của APK
if command -v apksigner &> /dev/null; then
    echo "[*] Kiểm tra chữ ký APK..."
    if apksigner verify "$FINAL_APK"; then
        echo "[✔] APK đã có chữ ký hợp lệ."
    else
        echo "[!] APK chưa có chữ ký, tiến hành ký..."

        # Tạo khóa keystore nếu chưa có
        if [ ! -f "my-release-key.jks" ]; then
            echo "[*] Tạo khóa ký APK..."
            keytool -genkey -v -keystore my-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykeyalias -storepass password -key-pass password -dname "CN=Android, OU=Dev, O=Company, L=City, S=State, C=US"
        fi

        # Ký APK
        apksigner sign --ks my-release-key.jks --ks-key-alias mykeyalias --ks-pass pass:password --key-pass pass:password --out "$SIGNED_APK" "$FINAL_APK"
        echo "[✔] APK đã được ký lại: $SIGNED_APK"
    fi
else
    echo "[!] Không tìm thấy 'apksigner', bỏ qua bước kiểm tra chữ ký!"
fi

echo "[✔] Quá trình hoàn tất! File APK sẵn sàng để cài đặt."
