#!/bin/bash

# Hàm gửi request giả lập như Firefox Android
req() {
    wget --header="User-Agent: Mozilla/5.0 (Android 13; Mobile; rv:125.0) Gecko/125.0 Firefox/125.0" \
         --header="Accept-Language: en-US,en;q=0.9" \
         --header="Connection: keep-alive" \
         --timeout=30 -nv -O "$@"
}

# Hàm tìm phiên bản mới nhất của Hay Day trên APKMirror
get_latest_version() {
    grep -oP 'class="fontBlack"[^>]*href="[^"]+"\s*>\K[^<]+' | sed 20q | awk '{print $NF}' | sort -V | tail -1
}

# Hàm lấy link tải APKM từ APKMirror
get_apkm_link() {
    local name="hay-day"
    local org="supercell"
    local dpi=""
    local arch="arm64-v8a"
    local type="BUNDLE"

    url="https://www.apkmirror.com/uploads/?appcategory=$name"
    version="${version:-$(req - "$url" | get_latest_version)}"
    url="https://www.apkmirror.com/apk/$org/$name/$name-${version//./-}-release"
    url="https://www.apkmirror.com$(req - "$url" | awk -v type="$type" '/apkm-badge/ && $0 ~ (">" type "</span>") {getline; print $0}' | grep -oP 'href="\K[^"]+')"
    url="https://www.apkmirror.com$(req - "$url" | grep -oP 'class="[^"]*downloadButton[^"]*"[^>]*href="\K[^"]+')"
    url="https://www.apkmirror.com$(req - "$url" | grep -oP 'id="download-link"[^>]*href="\K[^"]+')"

    echo "$url"
}

# Tải file APKM mới nhất của Hay Day
echo "[*] Đang tải Hay Day từ APKMirror..."
APKM_FILE="hay-day.apkm"
req "$APKM_FILE" "$(get_apkm_link)"

# Kiểm tra nếu tải không thành công
if [ ! -f "$APKM_FILE" ]; then
    echo "[!] Lỗi: Không thể tải file APKM!"
    exit 1
fi
echo "[✔] Tải thành công: $APKM_FILE"

# Kiểm tra nếu bundletool chưa có thì tải về
BUNDLETOOL_JAR="bundletool.jar"
if [ ! -f "$BUNDLETOOL_JAR" ]; then
    echo "[*] Đang tải bundletool..."
    req "$BUNDLETOOL_JAR" "https://github.com/google/bundletool/releases/latest/download/bundletool-all.jar"
fi

# Bước 1: Giải nén file APKM
EXTRACT_DIR="extracted_apkm"
echo "[*] Giải nén $APKM_FILE..."
unzip -o "$APKM_FILE" -d "$EXTRACT_DIR" || { echo "[!] Lỗi khi giải nén."; exit 1; }

# Bước 2: Hợp nhất Split APKs thành một APK duy nhất
FINAL_APK="final.apk"
SIGNED_APK="signed.apk"
echo "[*] Hợp nhất Split APKs..."
java -jar "$BUNDLETOOL_JAR" build-apks --mode=universal --apks="$EXTRACT_DIR/base.apks" --output="merged.apks"
unzip -o merged.apks -d final_apk
mv final_apk/universal.apk "$FINAL_APK"

# Bước 3: Kiểm tra chữ ký của APK
echo "[*] Kiểm tra chữ ký APK..."
if apksigner verify "$FINAL_APK"; then
    echo "[✔] APK đã có chữ ký hợp lệ."
else
    echo "[!] APK chưa có chữ ký, tiến hành ký..."

    # Tạo khóa keystore nếu chưa có
    if [ ! -f "my-release-key.jks" ]; then
        echo "[*] Tạo khóa ký APK..."
        keytool -genkey -v -keystore my-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykeyalias -storepass password -keypass password -dname "CN=Android, OU=Dev, O=Company, L=City, S=State, C=US"
    fi

    # Ký APK
    apksigner sign --ks my-release-key.jks --ks-key-alias mykeyalias --ks-pass pass:password --key-pass pass:password --out "$SIGNED_APK" "$FINAL_APK"
    echo "[✔] APK đã được ký lại: $SIGNED_APK"
fi

echo "[✔] Quá trình hoàn tất! File APK sẵn sàng để cài đặt."
