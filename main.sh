# Make requests like send from Firefox Android 
req() {
    wget --header="User-Agent: Mozilla/5.0 (Android 13; Mobile; rv:125.0) Gecko/125.0 Firefox/125.0" \
         --header="Content-Type: application/octet-stream" \
         --header="Accept-Language: en-US,en;q=0.9" \
         --header="Connection: keep-alive" \
         --header="Upgrade-Insecure-Requests: 1" \
         --header="Cache-Control: max-age=0" \
         --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" \
         --keep-session-cookies --timeout=30 -nv -O "$@"
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

# Best but sometimes not work because APKmirror protection 
apkmirror() {
    $1=$name
    $2=$dpi
    $3=$arch
    $4=$type
    url="https://www.apkmirror.com/uploads/?appcategory=$name"
    version="${version:-$(req - $url | get_apkmirror_version | get_latest_version)}"
    url="https://www.apkmirror.com/apk/$org/$name/$name-${version//./-}-release"
    url="https://www.apkmirror.com$(req - "$url" | extract_filtered_links "$dpi" "$arch" "$type")"
    url="https://www.apkmirror.com$(req - "$url" | grep -oP 'class="[^"]*downloadButton[^"]*"[^>]*href="\K[^"]+')"
    url="https://www.apkmirror.com$(req - "$url" | grep -oP 'id="download-link"[^>]*href="\K[^"]+')"
    req $name-v$version.apkm $url
}

apkmirror "hay-day" "" "arm64-v8a" "bundle"
